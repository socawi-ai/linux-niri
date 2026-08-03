#!/usr/bin/env bash
set -Eeuo pipefail

# Gives a Fedora/GRUB2/BLS machine a themed rEFInd boot screen without
# replacing anything Fedora already manages. rEFInd is installed as an
# ADDITIONAL firmware boot entry (NVRAM) alongside the existing "Fedora"
# entry that already points at shim -- nothing existing is deleted, so the
# firmware boot menu (F12/F2 at POST) can always fall back to the original
# entry even if rEFInd is misconfigured. rEFInd is themed with the
# rEFInd-nils theme and given exactly one manual menu entry that chainloads
# straight into Fedora's existing shim -> grub -> BLS kernel chain, with
# rEFInd's own filesystem auto-scan disabled so it can't also show a second,
# duplicate, auto-detected entry for the same install. GRUB's own timeout is
# then set to 0 so the handoff from rEFInd into grub is instant and
# invisible -- rEFInd is the only boot menu you actually see.
#
# Companion to fedora-niri-setup.sh in this repo, but fully standalone --
# does not require it to have been run first.

TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
ASSUME_YES="${ASSUME_YES:-1}"

# rEFInd has no official Fedora/COPR package; upstream ships version-pinned
# RPMs on SourceForge with no stable "latest" alias, so the version is
# pinned here and overridable.
REFIND_VERSION="${REFIND_VERSION:-0.14.2}"
REFIND_RPM_URL="${REFIND_RPM_URL:-https://sourceforge.net/projects/refind/files/${REFIND_VERSION}/refind-${REFIND_VERSION}-1.x86_64.rpm/download}"

# Same theme repo arch-niri-setup.sh uses. Confirmed to ship icons/os_fedora.png.
REFIND_THEME_REPO="${REFIND_THEME_REPO:-https://github.com/NilsPvR/rEFInd-nils}"
REFIND_THEME_NAME="${REFIND_THEME_NAME:-rEFInd-nils}"
REFIND_THEME_DIR="${REFIND_THEME_DIR:-$HOME/.cache/fedora-refind-setup/refind-theme}"
REFIND_THEME_DIR_WAS_SET=0
[[ -n "${REFIND_THEME_DIR+x}" ]] && REFIND_THEME_DIR_WAS_SET=1

# Explicit override if find_refind_conf()/resolve_esp_mount() can't locate
# things on their own (unusual ESP mount point or layout).
REFIND_CONF_PATH="${REFIND_CONF_PATH:-}"
ESP_MOUNT_OVERRIDE="${ESP_MOUNT_OVERRIDE:-}"

# Path (relative to the ESP root) of the shim binary Fedora's own firmware
# boot entry already points at -- confirmed via `efibootmgr -v` on a stock
# Fedora UEFI install (\EFI\FEDORA\SHIMX64.EFI). rEFInd's manual menu entry
# chainloads to this exact file, so it boots through the same trusted path
# Fedora's own entry already uses.
REFIND_SHIM_LOADER_PATH="${REFIND_SHIM_LOADER_PATH:-/EFI/fedora/shimx64.efi}"

# --shim makes rEFInd install itself so a Secure-Boot-signed shim launches it
# (rather than rEFInd's own unsigned binary), and --localkeys has rEFInd
# self-sign its binaries/drivers so there's a key ready to trust. Together
# these mean: if Secure Boot is ever turned on later, this install doesn't
# need to be redone -- BUT a one-time interactive MOK enrollment (approving
# rEFInd's key in the blue MokManager screen at the next boot) is still
# required at that point. That step is inherently physical-presence-only and
# cannot be scripted; this is a deliberate anti-malware property of the MOK
# protocol, not a gap in this script. Harmless no-ops while Secure Boot is
# off, which is rEFInd's and this machine's current state.
REFIND_USE_SHIM="${REFIND_USE_SHIM:-1}"
REFIND_USE_LOCALKEYS="${REFIND_USE_LOCALKEYS:-1}"

REFIND_MENUENTRY_LABEL="${REFIND_MENUENTRY_LABEL:-Fedora}"
REFIND_MENUENTRY_ICON="${REFIND_MENUENTRY_ICON:-themes/$REFIND_THEME_NAME/icons/os_fedora.png}"
# Excludes "internal" so rEFInd's own ESP filesystem scan can't also surface
# an auto-detected duplicate of the entry defined manually below; keeps
# "external,optical" so a USB installer/rescue disk still shows up if one is
# plugged in.
REFIND_SCANFOR="${REFIND_SCANFOR:-manual,external,optical}"
REFIND_TIMEOUT_SECONDS="${REFIND_TIMEOUT_SECONDS:-10}"
# Without an explicit resolution, rEFInd auto-picks a GOP mode that often
# doesn't match the real display, so the theme's fillscreen banner and icons
# render distorted/misplaced. Matches this repo's existing GRUB_GFXMODE
# default (fedora-niri-setup.sh) for the same ultrawide display. Set to ""
# to leave resolution unset (rEFInd's own auto-detect).
REFIND_RESOLUTION_WIDTH="${REFIND_RESOLUTION_WIDTH:-3440}"
REFIND_RESOLUTION_HEIGHT="${REFIND_RESOLUTION_HEIGHT:-1440}"

# rEFInd is the visible boot menu now, so GRUB's own menu is set to boot
# instantly once rEFInd hands off to it -- avoids a second, redundant menu.
GRUB_TIMEOUT_TARGET="${GRUB_TIMEOUT_TARGET:-0}"
GRUB_TIMEOUT_STYLE_TARGET="${GRUB_TIMEOUT_STYLE_TARGET:-hidden}"
GRUB_CONFIG_FILE="${GRUB_CONFIG_FILE:-/etc/default/grub}"
# /boot/grub2/grub.cfg is a symlink into the ESP (see /etc/grub2-efi.cfg) --
# this is Fedora's own distro-normalized path for grub2-mkconfig -o on EFI
# systems, not a BIOS-only path; it resolves to the real
# /boot/efi/EFI/fedora/grub.cfg that shim/grub actually read.
GRUB_MKCONFIG_OUTPUT="${GRUB_MKCONFIG_OUTPUT:-/boot/grub2/grub.cfg}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_FILE:-$HOME/fedora-refind-setup-$TIMESTAMP.log}"
SYSTEM_BACKUP_ROOT="${SYSTEM_BACKUP_ROOT:-/var/backups/fedora-refind-setup/$TIMESTAMP}"

TARGET_HOME="$HOME"
DNF_BIN=""
DNF_SKIP_UNAVAILABLE_SUPPORTED=""
ESP_MOUNT=""
REFIND_SHIM_ABS_PATH=""
REFIND_BOOT_NUM=""
SECURE_BOOT_STATE="unknown"
STEP_COUNT=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_BOLD=$'\033[1m'
  COLOR_BLUE=$'\033[1;34m'
  COLOR_GREEN=$'\033[1;32m'
  COLOR_YELLOW=$'\033[1;33m'
  COLOR_RED=$'\033[1;31m'
  COLOR_DIM=$'\033[2m'
else
  COLOR_RESET=""
  COLOR_BOLD=""
  COLOR_BLUE=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_DIM=""
fi

TOTAL_SECTIONS=5

declare -a CHANGES=()
declare -a WARNINGS=()
declare -a SYSTEM_BACKUPS=()

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'die "Setup failed on or near line $LINENO. Review $LOG_FILE, fix the reported problem, then re-run the script. Nothing this script does removes your existing Fedora firmware boot entry, so the machine will still boot normally in the meantime."' ERR

print_banner() {
  printf '\n'
  printf '%s  ╭──────────────────────────────────────────────────────╮%s\n' "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  │                                                      │%s\n' "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  │  %sFedora rEFInd Setup%s                                 │%s\n' "$COLOR_BLUE" "$COLOR_BOLD" "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  │  %sThemed rEFInd boot screen for Fedora%s                │%s\n' "$COLOR_BLUE" "$COLOR_DIM" "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  │                                                      │%s\n' "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  ╰──────────────────────────────────────────────────────╯%s\n' "$COLOR_BLUE" "$COLOR_RESET"
  printf '\n'
}

section() {
  STEP_COUNT=$((STEP_COUNT + 1))
  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  [ %02d / %02d ]  %s%s\n' "$COLOR_BLUE" "$STEP_COUNT" "$TOTAL_SECTIONS" "$*" "$COLOR_RESET"
  printf '%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_BLUE" "$COLOR_RESET"
}

log() {
  printf '  %s✓%s  %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

warn() {
  WARNINGS+=("$*")
  printf '  %s⚠%s  %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
}

die() {
  printf '\n  %s✗  ERROR:%s %s\n\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2
  exit 1
}

record_change() {
  CHANGES+=("$*")
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

run_sudo() {
  sudo "$@"
}

run_as_user() {
  if [[ "$(id -un)" == "$TARGET_USER" ]]; then
    "$@"
  else
    sudo -u "$TARGET_USER" -H "$@"
  fi
}

ask_value() {
  local prompt="$1"
  local default="${2:-}"
  local answer

  if [[ "$ASSUME_YES" == "1" ]]; then
    printf '%s\n' "$default"
    return 0
  fi

  [[ -r /dev/tty && -w /dev/tty ]] || die "A value is required, but no interactive terminal is available. Re-run from a terminal or set ASSUME_YES=1."
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$prompt" "$default" >/dev/tty
  else
    printf '%s: ' "$prompt" >/dev/tty
  fi
  IFS= read -r answer </dev/tty
  printf '%s\n' "${answer:-$default}"
}

require_fedora_uefi() {
  [[ "$EUID" -ne 0 ]] || die "Run this script as your normal user, not directly as root."
  [[ -f /etc/fedora-release ]] || die "This script is intended for Fedora Linux."
  [[ -d /sys/firmware/efi ]] || die "This machine is not booted in UEFI mode. rEFInd requires UEFI; it cannot be installed on legacy BIOS boots."

  if have_command dnf5; then
    DNF_BIN="dnf5"
  elif have_command dnf; then
    DNF_BIN="dnf"
  else
    die "Neither dnf5 nor dnf was found."
  fi
}

resolve_target_user() {
  if [[ "$ASSUME_YES" != "1" ]]; then
    TARGET_USER="$(ask_value "Target username (used only for the rEFInd/theme download cache)" "$TARGET_USER")"
  fi

  [[ "$TARGET_USER" != "root" ]] || die "Refusing to run as root's own user; re-run as your normal user."
  getent passwd "$TARGET_USER" >/dev/null || die "User '$TARGET_USER' does not exist."

  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$TARGET_HOME" ]] || die "Could not determine home directory for $TARGET_USER."

  if [[ "$REFIND_THEME_DIR_WAS_SET" == "0" ]]; then
    REFIND_THEME_DIR="$TARGET_HOME/.cache/fedora-refind-setup/refind-theme"
  fi

  log "Target user: $TARGET_USER"
  log "rEFInd version: $REFIND_VERSION"
}

prepare_runtime() {
  run_sudo install -d -m 0755 "$SYSTEM_BACKUP_ROOT"
  run_sudo -v
  log "Log file: $LOG_FILE"
  log "System backups: $SYSTEM_BACKUP_ROOT"
}

already_backed_up() {
  local path="$1"
  shift
  local seen
  for seen in "$@"; do
    [[ "$seen" == "$path" ]] && return 0
  done
  return 1
}

backup_system_path() {
  local path="$1"
  run_sudo test -e "$path" || return 0
  if already_backed_up "$path" "${SYSTEM_BACKUPS[@]}"; then
    return 0
  fi

  local dest="$SYSTEM_BACKUP_ROOT$path"
  run_sudo install -d -m 0755 "$(dirname "$dest")"
  run_sudo cp -a "$path" "$dest"
  SYSTEM_BACKUPS+=("$path")
  log "Backed up system path $path -> $dest"
}

write_system_file() {
  local path="$1"
  local mode="${2:-0644}"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  backup_system_path "$path"
  run_sudo install -D -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}

safe_rm_rf() {
  local path="$1"
  [[ -n "$path" && "$path" != "/" ]] || die "Refusing to remove unsafe path: $path"

  case "$path" in
    "$TARGET_HOME"/*)
      run_as_user rm -rf -- "$path"
      ;;
    /tmp/*|/var/tmp/*)
      run_as_user rm -rf -- "$path"
      ;;
    *)
      die "Refusing to remove $path because it is outside the expected user or temporary directories."
      ;;
  esac
}

dnf_install() {
  local packages=("$@")
  local args=(install)

  [[ "$ASSUME_YES" == "1" ]] && args+=(-y)

  if [[ -z "$DNF_SKIP_UNAVAILABLE_SUPPORTED" ]]; then
    if "$DNF_BIN" install --help 2>&1 | grep -q -- '--skip-unavailable'; then
      DNF_SKIP_UNAVAILABLE_SUPPORTED=1
    else
      DNF_SKIP_UNAVAILABLE_SUPPORTED=0
    fi
  fi
  [[ "$DNF_SKIP_UNAVAILABLE_SUPPORTED" == "1" ]] && args+=(--skip-unavailable)

  run_sudo "$DNF_BIN" "${args[@]}" "${packages[@]}"
}

dnf_install_optional() {
  if dnf_install "$@"; then
    return 0
  fi
  warn "Could not install optional package set: $*"
  return 1
}

dnf_install_best_effort() {
  local packages=("$@")
  local package
  if dnf_install "${packages[@]}"; then
    return 0
  fi
  warn "Batch package install failed; retrying packages one at a time and skipping failures."
  for package in "${packages[@]}"; do
    dnf_install_optional "$package" || true
  done
  return 0
}

download_as_user() {
  local url="$1"
  local dest="$2"

  run_as_user mkdir -p "$(dirname "$dest")"
  run_as_user curl -fL "$url" -o "$dest"
}

clone_or_update_git_repo() {
  local repo_url="$1"
  local repo_dir="$2"

  run_as_user mkdir -p "$(dirname "$repo_dir")"

  if [[ -d "$repo_dir/.git" ]]; then
    local current_url
    current_url="$(run_as_user git -C "$repo_dir" config --get remote.origin.url || true)"
    if [[ "$current_url" != "$repo_url" ]]; then
      warn "$repo_dir has origin $current_url, not $repo_url. Removing and cloning fresh."
      safe_rm_rf "$repo_dir"
      run_as_user git clone "$repo_url" "$repo_dir"
    else
      log "Updating repository at $repo_dir."
      run_as_user git -C "$repo_dir" fetch --prune
      run_as_user git -C "$repo_dir" pull --ff-only
    fi
  elif [[ -e "$repo_dir" ]]; then
    warn "$repo_dir exists but is not a git repository. Removing and cloning fresh."
    safe_rm_rf "$repo_dir"
    run_as_user git clone "$repo_url" "$repo_dir"
  else
    log "Cloning $repo_url to $repo_dir."
    run_as_user git clone "$repo_url" "$repo_dir"
  fi
}

detect_secure_boot() {
  if ! have_command mokutil; then
    dnf_install_best_effort mokutil
  fi

  if have_command mokutil; then
    local sb_out
    sb_out="$(run_sudo mokutil --sb-state 2>&1 || true)"
    if grep -qi 'SecureBoot enabled' <<<"$sb_out"; then
      SECURE_BOOT_STATE="enabled"
    elif grep -qi 'SecureBoot disabled' <<<"$sb_out"; then
      SECURE_BOOT_STATE="disabled"
    else
      SECURE_BOOT_STATE="unknown"
    fi
  else
    warn "mokutil is not available; could not determine Secure Boot state."
  fi

  log "Secure Boot state: $SECURE_BOOT_STATE"
  if [[ "$SECURE_BOOT_STATE" == "enabled" ]]; then
    warn "Secure Boot is currently ENABLED. This script will still install rEFInd via --shim/--localkeys, but you will need to approve rEFInd's key in the blue MokManager screen at the very next reboot, or the machine will not boot into rEFInd. If that happens, use the firmware boot menu (F12/F2 at POST) to select the original 'Fedora' entry directly -- it is untouched."
  fi
}

resolve_esp_mount() {
  if [[ -n "$ESP_MOUNT_OVERRIDE" ]]; then
    if run_sudo test -f "$ESP_MOUNT_OVERRIDE$REFIND_SHIM_LOADER_PATH"; then
      ESP_MOUNT="$ESP_MOUNT_OVERRIDE"
    else
      die "ESP_MOUNT_OVERRIDE=$ESP_MOUNT_OVERRIDE does not contain $REFIND_SHIM_LOADER_PATH."
    fi
  else
    local candidates=(/boot/efi /efi /boot)
    local vfat_target
    while IFS= read -r vfat_target; do
      [[ -n "$vfat_target" ]] || continue
      candidates+=("$vfat_target")
    done < <(findmnt -rn -o TARGET --types vfat 2>/dev/null || true)

    local c
    for c in "${candidates[@]}"; do
      [[ -n "$c" ]] || continue
      if run_sudo test -f "$c$REFIND_SHIM_LOADER_PATH"; then
        ESP_MOUNT="$c"
        break
      fi
    done
  fi

  [[ -n "$ESP_MOUNT" ]] || die "Could not find $REFIND_SHIM_LOADER_PATH under /boot/efi, /efi, /boot, or any mounted vfat filesystem. Set ESP_MOUNT_OVERRIDE and/or REFIND_SHIM_LOADER_PATH if your layout is unusual."

  REFIND_SHIM_ABS_PATH="$ESP_MOUNT$REFIND_SHIM_LOADER_PATH"
  log "EFI System Partition: $ESP_MOUNT"
  log "Fedora shim loader: $REFIND_SHIM_ABS_PATH"
}

install_refind_package() {
  local installed_version
  installed_version="$(rpm -q --qf '%{VERSION}' refind 2>/dev/null || true)"
  if [[ "$installed_version" == "$REFIND_VERSION" ]] && have_command refind-install; then
    log "refind $REFIND_VERSION is already installed."
    return 0
  fi

  local rpm_path="$TARGET_HOME/.cache/fedora-refind-setup/downloads/refind-${REFIND_VERSION}-1.x86_64.rpm"
  if run_as_user test -f "$rpm_path" && file "$rpm_path" 2>/dev/null | grep -qi 'RPM'; then
    log "Using already-downloaded rEFInd $REFIND_VERSION package."
  else
    log "Downloading rEFInd $REFIND_VERSION."
    download_as_user "$REFIND_RPM_URL" "$rpm_path" || die "Could not download rEFInd from $REFIND_RPM_URL. Check REFIND_VERSION / REFIND_RPM_URL."
    # SourceForge occasionally serves an HTML interstitial instead of
    # redirecting straight to the file; make sure we actually got an RPM
    # before handing it to dnf.
    file "$rpm_path" 2>/dev/null | grep -qi 'RPM' || \
      die "Downloaded file at $rpm_path is not an RPM (SourceForge likely served an interstitial page instead of the file). Check REFIND_RPM_URL, or download the .rpm manually and set REFIND_RPM_URL=file://<path>."
  fi

  # The rEFInd RPM is an upstream release asset with no Fedora/RPM Fusion
  # signing key configured on this system; skip the local-package GPG check
  # explicitly rather than relying on dnf's default (which varies by config)
  # so this doesn't silently hang waiting on a prompt under ASSUME_YES=1.
  local args=(install --setopt=localpkg_gpgcheck=0)
  [[ "$ASSUME_YES" == "1" ]] && args+=(-y)
  run_sudo "$DNF_BIN" "${args[@]}" "$rpm_path" || die "Could not install the downloaded rEFInd package."

  have_command refind-install || die "rEFInd package installed, but refind-install was not found in PATH."
  record_change "Installed rEFInd $REFIND_VERSION."
}

run_refind_install() {
  if [[ "$REFIND_USE_LOCALKEYS" == "1" ]] && ! have_command sbsign; then
    log "Installing sbsigntools (provides sbsign, required by --localkeys)."
    dnf_install_best_effort sbsigntools
    have_command sbsign || die "sbsign still not found after installing sbsigntools; refind-install --localkeys cannot proceed. Set REFIND_USE_LOCALKEYS=0 to skip self-signing, or install sbsigntools manually."
  fi

  log "Recording current firmware boot entries for the log (nothing below this line is removed by rEFInd's installer)."
  run_sudo efibootmgr -v || true

  # --shim copies the given shim binary into rEFInd's own EFI/refind/
  # directory and renames rEFInd's own binary to grubx64.efi there (shim is
  # hard-coded to chainload a same-directory file with that exact name) --
  # it does NOT reuse Fedora's existing NVRAM entry. The result is a new,
  # separate, Secure-Boot-capable boot path into rEFInd, additive to (not a
  # replacement for) Fedora's own untouched "Fedora" entry.
  local args=()
  [[ "$REFIND_USE_SHIM" == "1" ]] && args+=(--shim "$REFIND_SHIM_ABS_PATH")
  [[ "$REFIND_USE_LOCALKEYS" == "1" ]] && args+=(--localkeys)
  # Without --yes, refind-install blocks on its own interactive prompts
  # (e.g. "you specified --shim but Secure Boot isn't on, continue?") --
  # only auto-answer them when the rest of this script is also non-interactive.
  [[ "$ASSUME_YES" == "1" ]] && args+=(--yes)

  log "Running: refind-install ${args[*]}"
  run_sudo refind-install "${args[@]}" || die "refind-install failed. Your existing 'Fedora' firmware boot entry is untouched; the machine will still boot normally."

  log "Firmware boot entries after install:"
  local after_entries
  after_entries="$(run_sudo efibootmgr -v || true)"
  printf '%s\n' "$after_entries"

  # refind-install --shim intentionally registers TWO entries: a
  # shim-chained one (Secure-Boot-capable, what actually boots) and a
  # "(direct)" one that bypasses shim entirely -- that pair is expected, not
  # a duplicate. Prefer the shim-chained entry (its title has no "(direct)"
  # suffix) for the rollback instructions printed in the summary.
  REFIND_BOOT_NUM="$(grep -oE '^Boot[0-9A-Fa-f]{4}\*? rEFInd Boot Manager$' <<<"$after_entries" | head -1 | grep -oE '[0-9A-Fa-f]{4}' | head -1 || true)"
  [[ -n "$REFIND_BOOT_NUM" ]] || REFIND_BOOT_NUM="$(grep -oE '^Boot[0-9A-Fa-f]{4}\*? rEFInd' <<<"$after_entries" | head -1 | grep -oE '[0-9A-Fa-f]{4}' | head -1 || true)"

  local refind_entry_count expected_entries=1
  [[ "$REFIND_USE_SHIM" == "1" ]] && expected_entries=2
  refind_entry_count="$(grep -cE '^Boot[0-9A-Fa-f]{4}\*? rEFInd' <<<"$after_entries" || true)"
  if [[ "${refind_entry_count:-0}" -gt "$expected_entries" ]]; then
    warn "Found $refind_entry_count firmware boot entries labeled 'rEFInd' (expected $expected_entries: refind-install --shim always creates a shim-chained entry plus a '(direct)' bypass entry). Remove stale duplicates with: sudo efibootmgr -b <NUM> -B"
  fi

  record_change "Installed and registered rEFInd as firmware boot entry Boot${REFIND_BOOT_NUM:-?} (existing Fedora entry left in place)."
}

find_refind_conf() {
  if [[ -n "$REFIND_CONF_PATH" ]]; then
    if run_sudo test -f "$REFIND_CONF_PATH"; then
      printf '%s\n' "$REFIND_CONF_PATH"
      return 0
    fi
    warn "REFIND_CONF_PATH=$REFIND_CONF_PATH does not exist; falling back to searching for it."
  fi

  local hit
  hit="$(run_sudo find "$ESP_MOUNT" -maxdepth 4 -iname 'refind.conf' 2>/dev/null | head -1)"
  [[ -n "$hit" ]] && { printf '%s\n' "$hit"; return 0; }

  return 1
}

install_refind_theme() {
  local refind_conf="$1"

  log "Fetching rEFInd theme from $REFIND_THEME_REPO."
  clone_or_update_git_repo "$REFIND_THEME_REPO" "$REFIND_THEME_DIR"

  [[ -f "$REFIND_THEME_DIR/theme.conf" ]] || {
    warn "$REFIND_THEME_DIR has no theme.conf; not a valid rEFInd theme, skipping theme install."
    return 0
  }

  local refind_dir theme_dest
  refind_dir="$(dirname "$refind_conf")"
  theme_dest="$refind_dir/themes/$REFIND_THEME_NAME"

  backup_system_path "$theme_dest"
  run_sudo rm -rf "$theme_dest"
  run_sudo install -d -m 0755 "$(dirname "$theme_dest")"

  local tmp_theme; tmp_theme="$(mktemp -d)"
  cp -r "$REFIND_THEME_DIR/." "$tmp_theme/"
  rm -rf "$tmp_theme/.git"
  # -r, not -a: the ESP is vfat, which has no concept of Unix ownership --
  # cp -a always fails trying to chown there, even as root.
  run_sudo mkdir -p "$theme_dest"
  run_sudo cp -r "$tmp_theme/." "$theme_dest/"
  rm -rf "$tmp_theme"

  run_sudo test -f "$theme_dest/theme.conf" || \
    die "Theme copy to $theme_dest failed -- theme.conf missing after copy."

  log "Installed rEFInd theme '$REFIND_THEME_NAME' to $theme_dest."
  record_change "Installed rEFInd theme '$REFIND_THEME_NAME' from $REFIND_THEME_REPO."

  if run_sudo grep -qE "^include[[:space:]]+themes/${REFIND_THEME_NAME}/theme\.conf[[:space:]]*\$" "$refind_conf"; then
    log "Theme already included in $refind_conf."
    return 0
  fi

  backup_system_path "$refind_conf"
  local tmp; tmp="$(mktemp)"
  run_sudo cat "$refind_conf" >"$tmp"
  printf '\ninclude themes/%s/theme.conf\n' "$REFIND_THEME_NAME" >>"$tmp"
  run_sudo install -m 0644 "$tmp" "$refind_conf"
  rm -f "$tmp"

  log "Added theme include to $refind_conf."
  record_change "Enabled rEFInd theme '$REFIND_THEME_NAME' in $refind_conf."
}

configure_refind_boot_entry() {
  local refind_conf="$1"
  local marker_begin="# BEGIN fedora-refind-setup generated boot configuration"
  local marker_end="# END fedora-refind-setup generated boot configuration"

  backup_system_path "$refind_conf"

  local tmp; tmp="$(mktemp)"
  run_sudo awk -v marker_begin="$marker_begin" -v marker_end="$marker_end" '
    $0 == marker_begin { skipping = 1; next }
    $0 == marker_end   { skipping = 0; next }
    !skipping { print }
  ' "$refind_conf" >"$tmp"

  [[ ! -s "$tmp" ]] || printf '\n' >>"$tmp"

  # Theme `include` paths are relative to refind.conf's own directory, but
  # the `icon` directive INSIDE a manual menuentry is documented as "a
  # complete path from the root of the current directory, not relative to
  # the default icons subdirectory" -- i.e. it needs an ESP-root-absolute
  # path with a leading slash, the same convention `loader` already uses.
  # Mixing these two conventions up produces no error, just rEFInd's
  # broken-image placeholder (black/yellow hazard stripes) at boot.
  local refind_dir icon_esp_path icon_line=""
  refind_dir="$(dirname "$refind_conf")"
  icon_esp_path="${refind_dir#"$ESP_MOUNT"}/$REFIND_MENUENTRY_ICON"
  if run_sudo test -f "$refind_dir/$REFIND_MENUENTRY_ICON"; then
    icon_line="    icon     $icon_esp_path"
  else
    warn "Theme icon $REFIND_MENUENTRY_ICON not found next to $refind_conf; omitting it (rEFInd will fall back to its default icon)."
  fi

  local resolution_line=""
  if [[ -n "$REFIND_RESOLUTION_WIDTH" && -n "$REFIND_RESOLUTION_HEIGHT" ]]; then
    resolution_line="resolution $REFIND_RESOLUTION_WIDTH $REFIND_RESOLUTION_HEIGHT"
  fi

  cat >>"$tmp" <<EOF
$marker_begin
timeout $REFIND_TIMEOUT_SECONDS
scanfor $REFIND_SCANFOR
$resolution_line

menuentry "$REFIND_MENUENTRY_LABEL" {
$icon_line
    loader   $REFIND_SHIM_LOADER_PATH
    ostype   Linux
    graphics on
}
$marker_end
EOF

  run_sudo install -m 0644 "$tmp" "$refind_conf"
  rm -f "$tmp"

  log "Configured a single '$REFIND_MENUENTRY_LABEL' entry in $refind_conf (chainloads $REFIND_SHIM_LOADER_PATH), timeout ${REFIND_TIMEOUT_SECONDS}s, auto-scan restricted to: $REFIND_SCANFOR, resolution: ${REFIND_RESOLUTION_WIDTH:-auto}${REFIND_RESOLUTION_WIDTH:+x}${REFIND_RESOLUTION_HEIGHT}."
  record_change "Configured rEFInd's boot menu entry and timeout in $refind_conf."
}

upsert_grub_default() {
  local key="$1"
  local value="$2"
  local path="$GRUB_CONFIG_FILE"
  local tmp

  run_sudo test -f "$path" || {
    warn "$path does not exist; skipping GRUB default update for $key."
    return 0
  }

  backup_system_path "$path"
  tmp="$(mktemp)"

  run_sudo awk -v key="$key" -v value="$value" '
    BEGIN { replaced = 0 }
    $0 ~ "^[[:space:]]*#?[[:space:]]*" key "=" {
      print key "=" value
      replaced = 1
      next
    }
    { print }
    END {
      if (!replaced) print key "=" value
    }
  ' "$path" >"$tmp"

  run_sudo install -m 0644 "$tmp" "$path"
  rm -f "$tmp"
}

configure_grub_timeout() {
  log "Setting GRUB_TIMEOUT=$GRUB_TIMEOUT_TARGET and GRUB_TIMEOUT_STYLE=$GRUB_TIMEOUT_STYLE_TARGET in $GRUB_CONFIG_FILE (instant handoff once rEFInd chainloads into grub)."
  upsert_grub_default GRUB_TIMEOUT "\"$GRUB_TIMEOUT_TARGET\""
  # "hidden" (rather than just timeout=0 with the existing "menu" style)
  # guarantees no menu flash during the rEFInd -> grub handoff. The GRUB
  # menu is still reachable by holding Shift/Esc during boot -- this is
  # intentional, not a loss of the fallback path.
  upsert_grub_default GRUB_TIMEOUT_STYLE "\"$GRUB_TIMEOUT_STYLE_TARGET\""

  if have_command grub2-mkconfig; then
    run_sudo grub2-mkconfig -o "$GRUB_MKCONFIG_OUTPUT"
    record_change "Set GRUB_TIMEOUT=$GRUB_TIMEOUT_TARGET, GRUB_TIMEOUT_STYLE=$GRUB_TIMEOUT_STYLE_TARGET, and regenerated $GRUB_MKCONFIG_OUTPUT."
  else
    warn "grub2-mkconfig was not found; $GRUB_CONFIG_FILE was updated but grub.cfg was not regenerated. Run 'sudo grub2-mkconfig -o $GRUB_MKCONFIG_OUTPUT' manually."
  fi
}

print_summary() {
  local item

  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  Setup complete%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '\n'
  printf '  Log:            %s\n' "$LOG_FILE"
  printf '  System backups: %s\n' "$SYSTEM_BACKUP_ROOT"

  if ((${#CHANGES[@]})); then
    printf '\n  %sChanges:%s\n' "$COLOR_GREEN" "$COLOR_RESET"
    for item in "${CHANGES[@]}"; do
      printf '  %s✓%s  %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$item"
    done
  fi

  if ((${#WARNINGS[@]})); then
    printf '\n  %sWarnings:%s\n' "$COLOR_YELLOW" "$COLOR_RESET"
    for item in "${WARNINGS[@]}"; do
      printf '  %s⚠%s  %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$item"
    done
  fi

  printf '\n  %sTo undo, if you ever need to:%s\n' "$COLOR_DIM" "$COLOR_RESET"
  if [[ -n "$REFIND_BOOT_NUM" ]]; then
    printf '  1. sudo efibootmgr -b %s -B             # removes the rEFInd firmware boot entry (Boot%s)\n' "$REFIND_BOOT_NUM" "$REFIND_BOOT_NUM"
  else
    printf '  1. sudo efibootmgr -v                  # find the "rEFInd" boot entry number (Boot####), then:\n'
    printf '     sudo efibootmgr -b <####> -B         # remove it\n'
  fi
  printf '  2. sudo cp -a %s/etc/default/grub /etc/default/grub   # restore the pre-change GRUB timeout\n' "$SYSTEM_BACKUP_ROOT"
  printf '  3. sudo grub2-mkconfig -o %s\n' "$GRUB_MKCONFIG_OUTPUT"
  printf '  Your original "Fedora" firmware boot entry was never modified or removed, so the F12/F2 firmware boot menu can always select it directly as a fallback.\n'

  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n' "$COLOR_GREEN" "$COLOR_RESET"
}

main() {
  print_banner
  section "Preflight"
  require_fedora_uefi
  resolve_target_user
  prepare_runtime
  detect_secure_boot
  resolve_esp_mount

  section "Install rEFInd"
  install_refind_package
  run_refind_install

  section "Theme and boot entry"
  local refind_conf
  refind_conf="$(find_refind_conf || true)"
  [[ -n "$refind_conf" ]] || die "refind-install succeeded, but no refind.conf was found under $ESP_MOUNT afterward."
  install_refind_theme "$refind_conf"
  configure_refind_boot_entry "$refind_conf"

  section "GRUB handoff"
  configure_grub_timeout

  section "Summary"
  print_summary
}

main "$@"
