#!/usr/bin/env bash
set -Eeuo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# rEFInd UEFI boot manager — standalone script
# ═══════════════════════════════════════════════════════════════════════════════
#
# Installs rEFInd as the primary UEFI boot manager. This does NOT replace
# GRUB or boot Linux kernels directly: GRUB stays installed exactly as it
# is, and rEFInd simply chainloads into it — its normal boot-loader auto-scan
# finds the existing EFI/fedora/grubx64.efi and offers it as a menu entry.
# GRUB itself is configured for an instant, silent boot (GRUB_TIMEOUT=0,
# hidden menu), so in practice: firmware -> rEFInd -> GRUB -> Linux, with no
# visible menus unless you interact with rEFInd's own timeout.
#
# Split out of fedora-niri-setup.sh so bootloader changes can be run, tested,
# and re-run independently of the desktop setup.
#
# Package: rEFInd (case-sensitive) — available in Fedora's official repos.
#   Provides refind-install, which does the actual ESP deployment and NVRAM
#   registration: dnf install rEFInd; refind-install
#
# Secure Boot note: Fedora's rEFInd package is not signed with the Fedora
# Secure Boot key. If SB is enabled, this script runs refind-install with
# --localkeys (self-signs with a freshly generated local key). Because the
# script runs non-interactively, you must manually enroll that key as a MOK
# afterwards (exact command is printed in the summary).
#
# Theme: installs a visual theme from a git repo following the standard
# rEFInd theme layout (banner/, icons/, selection/, theme.conf). Defaults to
# https://github.com/NilsPvR/rEFInd-nils. Set INSTALL_REFIND_THEME=0 to skip.
#
# Usage:
#   ./refind-migrate.sh                       # interactive
#   ASSUME_YES=1 ./refind-migrate.sh           # non-interactive
#   INSTALL_REFIND_THEME=0 ./refind-migrate.sh # skip the visual theme
# ═══════════════════════════════════════════════════════════════════════════════

ASSUME_YES="${ASSUME_YES:-0}"
DNF_SKIP_UNAVAILABLE="${DNF_SKIP_UNAVAILABLE:-1}"

REFIND_TIMEOUT="${REFIND_TIMEOUT:-5}"
REFIND_ENTRY_LABEL="${REFIND_ENTRY_LABEL:-Fedora Linux}"
REFIND_ESP_SUBDIR="${REFIND_ESP_SUBDIR:-EFI/refind}"

# rEFInd visual theme. Set INSTALL_REFIND_THEME=0 to skip (default rEFInd
# look). Any git repo following the standard rEFInd theme layout
# (banner/, icons/, selection/, theme.conf) works here.
INSTALL_REFIND_THEME="${INSTALL_REFIND_THEME:-1}"
REFIND_THEME_REPO="${REFIND_THEME_REPO:-https://github.com/NilsPvR/rEFInd-nils}"
REFIND_THEME_NAME="${REFIND_THEME_NAME:-rEFInd-nils}"
REFIND_THEME_DIR="${REFIND_THEME_DIR:-$HOME/.cache/fedora-niri-setup/refind-theme}"

# Runtime state — populated by preflight functions; not user-configurable.
_REFIND_ESP=""
_REFIND_ESP_DISK=""
_REFIND_ESP_PARTNUM=""
_REFIND_ARCH=""
_REFIND_EFI_NAME=""
_REFIND_SECURE_BOOT=""
_REFIND_BOOT_NUM=""
_GRUB_BOOT_NUM=""
_REFIND_THEME_INSTALLED=""

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_FILE:-$HOME/refind-migrate-$TIMESTAMP.log}"
SYSTEM_BACKUP_ROOT="${SYSTEM_BACKUP_ROOT:-/var/backups/fedora-niri-setup/$TIMESTAMP}"
DNF_BIN=""
DNF_SKIP_UNAVAILABLE_SUPPORTED=""

declare -a CHANGES=()
declare -a WARNINGS=()
declare -a SYSTEM_BACKUPS=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_BOLD=$'\033[1m'
  COLOR_BLUE=$'\033[1;34m'
  COLOR_CYAN=$'\033[1;36m'
  COLOR_GREEN=$'\033[1;32m'
  COLOR_YELLOW=$'\033[1;33m'
  COLOR_RED=$'\033[1;31m'
  COLOR_DIM=$'\033[2m'
else
  COLOR_RESET=""
  COLOR_BOLD=""
  COLOR_BLUE=""
  COLOR_CYAN=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_DIM=""
fi

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'die "refind-migrate.sh failed on or near line $LINENO. Review $LOG_FILE, fix the reported problem, then re-run the script."' ERR

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

package_installed() {
  rpm -q "$1" >/dev/null 2>&1
}

run_sudo() {
  sudo "$@"
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local suffix
  local answer

  if [[ "$ASSUME_YES" == "1" ]]; then
    [[ "$default" =~ ^[yY]$ ]]
    return $?
  fi

  [[ -r /dev/tty && -w /dev/tty ]] || die "A decision is required, but no interactive terminal is available. Re-run from a terminal or set ASSUME_YES=1."
  case "$default" in
    y|Y) suffix="[Y/n]" ;;
    *) suffix="[y/N]" ;;
  esac

  while true; do
    printf '%s %s ' "$prompt" "$suffix" >/dev/tty
    IFS= read -r answer </dev/tty
    answer="${answer:-$default}"
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf 'Please answer yes or no.\n' >/dev/tty ;;
    esac
  done
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
  [[ -e "$path" ]] || return 0
  if already_backed_up "$path" "${SYSTEM_BACKUPS[@]}"; then
    return 0
  fi

  local dest="$SYSTEM_BACKUP_ROOT$path"
  run_sudo install -d -m 0755 "$(dirname "$dest")"
  run_sudo cp -a "$path" "$dest"
  SYSTEM_BACKUPS+=("$path")
  log "Backed up system path $path -> $dest"
}

dnf_install() {
  local packages=("$@")
  local args=(install)

  if [[ "$ASSUME_YES" == "1" ]]; then
    args+=(-y)
  fi

  if [[ "$DNF_SKIP_UNAVAILABLE" == "1" ]]; then
    if [[ -z "$DNF_SKIP_UNAVAILABLE_SUPPORTED" ]]; then
      if "$DNF_BIN" install --help 2>&1 | grep -q -- '--skip-unavailable'; then
        DNF_SKIP_UNAVAILABLE_SUPPORTED=1
      else
        DNF_SKIP_UNAVAILABLE_SUPPORTED=0
        warn "$DNF_BIN does not support --skip-unavailable; using best-effort package fallback instead."
      fi
    fi

    if [[ "$DNF_SKIP_UNAVAILABLE_SUPPORTED" == "1" ]]; then
      args+=(--skip-unavailable)
    fi
  fi

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
  local failed=0

  if dnf_install "${packages[@]}"; then
    return 0
  fi

  warn "Batch package install failed; retrying packages one at a time and skipping failures."
  for package in "${packages[@]}"; do
    if ! dnf_install_optional "$package"; then
      failed=1
    fi
  done

  if [[ "$failed" == "1" ]]; then
    warn "Some packages could not be installed. Continuing so later setup steps can run."
  fi

  return 0
}

require_fedora() {
  [[ "$EUID" -ne 0 ]] || die "Run this script as your normal user, not directly as root."
  [[ -f /etc/fedora-release ]] || die "This script is intended for Fedora Linux."

  if have_command dnf5; then
    DNF_BIN="dnf5"
  elif have_command dnf; then
    DNF_BIN="dnf"
  else
    die "Neither dnf5 nor dnf was found."
  fi
}

prepare_runtime() {
  run_sudo install -d -m 0755 "$SYSTEM_BACKUP_ROOT"
  run_sudo -v
  log "Log file: $LOG_FILE"
  log "System backups: $SYSTEM_BACKUP_ROOT"
}

refind_check_uefi() {
  [[ -d /sys/firmware/efi ]] || \
    die "This system is not booted in UEFI mode (/sys/firmware/efi absent). rEFInd requires UEFI."
  log "UEFI mode confirmed."
}

refind_check_deps() {
  local missing=()
  local cmd
  for cmd in efibootmgr findmnt lsblk od; do
    have_command "$cmd" || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    dnf_install_best_effort efibootmgr util-linux || true
    for cmd in "${missing[@]}"; do
      have_command "$cmd" || die "Required command not available after install attempt: $cmd"
    done
  fi
}

refind_detect_esp() {
  local esp="" fstype dev candidate
  local esp_type_guid="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"

  # 1. Well-known mountpoints first.
  for candidate in /boot/efi /efi /boot; do
    if mountpoint -q "$candidate" 2>/dev/null; then
      fstype="$(findmnt -n -o FSTYPE "$candidate" 2>/dev/null || true)"
      if [[ "$fstype" == "vfat" ]]; then
        esp="$candidate"
        break
      fi
    fi
  done

  # 2. Any mounted vfat filesystem that looks like an ESP (has an EFI/ dir).
  if [[ -z "$esp" ]]; then
    local target
    while IFS= read -r target; do
      [[ -n "$target" ]] || continue
      if [[ -d "${target}/EFI" || -d "${target}/efi" ]]; then
        esp="$target"
        break
      fi
    done < <(findmnt -rn -o TARGET --types vfat 2>/dev/null || true)
  fi

  # 3. GPT partition-type GUID fallback — identifies the ESP even if it's
  #    mounted somewhere unusual, and tells us if it exists but is unmounted.
  if [[ -z "$esp" ]]; then
    local esp_part esp_mount
    esp_part="$(lsblk -rno NAME,PARTTYPE 2>/dev/null | awk -v guid="$esp_type_guid" 'tolower($2) == guid {print $1; exit}')"
    if [[ -n "$esp_part" ]]; then
      esp_mount="$(lsblk -rno MOUNTPOINT "/dev/${esp_part}" 2>/dev/null | head -1)"
      if [[ -n "$esp_mount" ]]; then
        esp="$esp_mount"
      else
        die "Found an EFI System Partition (/dev/${esp_part}, by GPT type GUID) but it is not mounted. Mount it (e.g. 'sudo mount /dev/${esp_part} /boot/efi') and re-run."
      fi
    fi
  fi

  if [[ -z "$esp" ]]; then
    warn "ESP detection failed. Diagnostics:"
    warn "  Mounted vfat filesystems:"
    findmnt -rn -o TARGET,SOURCE,FSTYPE --types vfat 2>/dev/null | sed 's/^/    /' >&2 || true
    warn "  Partitions with GPT type GUID ${esp_type_guid}: (none matched)"
    warn "  All partitions (NAME, PARTTYPE, FSTYPE, MOUNTPOINTS):"
    lsblk -o NAME,PARTTYPE,FSTYPE,MOUNTPOINTS 2>/dev/null | sed 's/^/    /' >&2 || true
    die "Cannot detect EFI System Partition. Ensure it is mounted (vfat) and re-run."
  fi
  _REFIND_ESP="$esp"

  # --first-only + head -1: a target can have more than one mount stacked on
  # it (e.g. duplicate/propagated mounts in some VM setups), which would
  # otherwise make $dev a multi-line string that no single-line regex below
  # can match.
  dev="$(findmnt -rn -o SOURCE --first-only "$esp" 2>/dev/null | head -1 || true)"
  dev="${dev//[[:space:]]/}"
  [[ -n "$dev" ]] || die "Cannot determine block device backing ESP at $esp."
  dev="$(realpath "$dev" 2>/dev/null || printf '%s' "$dev")"

  local pkname partnum
  pkname="$(lsblk -rndo PKNAME "$dev" 2>/dev/null | head -1 || true)"
  partnum="$(lsblk -rndo PARTN "$dev" 2>/dev/null | head -1 || true)"
  pkname="${pkname//[[:space:]]/}"
  partnum="${partnum//[[:space:]]/}"

  if [[ -n "$pkname" && -n "$partnum" ]]; then
    _REFIND_ESP_DISK="/dev/$pkname"
    _REFIND_ESP_PARTNUM="$partnum"
  elif [[ "$dev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
    _REFIND_ESP_DISK="${BASH_REMATCH[1]}"
    _REFIND_ESP_PARTNUM="${BASH_REMATCH[2]}"
  elif [[ "$dev" =~ ^(/dev/[a-z]+)([0-9]+)$ ]]; then
    _REFIND_ESP_DISK="${BASH_REMATCH[1]}"
    _REFIND_ESP_PARTNUM="${BASH_REMATCH[2]}"
  else
    die "Cannot parse disk/partition from $dev. Set REFIND_ESP_DISK and REFIND_ESP_PARTNUM manually."
  fi

  [[ -b "$_REFIND_ESP_DISK" ]] || die "Detected disk $_REFIND_ESP_DISK is not a block device."
  log "ESP: $_REFIND_ESP (device: $dev, disk: $_REFIND_ESP_DISK, part: $_REFIND_ESP_PARTNUM)."
}

refind_detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64)  _REFIND_ARCH="x64";  _REFIND_EFI_NAME="refind_x64.efi"  ;;
    aarch64) _REFIND_ARCH="aa64"; _REFIND_EFI_NAME="refind_aa64.efi" ;;
    i?86)    _REFIND_ARCH="ia32"; _REFIND_EFI_NAME="refind_ia32.efi" ;;
    *) die "Unsupported architecture for rEFInd: $machine." ;;
  esac
  log "Arch: $machine → rEFInd binary: $_REFIND_EFI_NAME."
}

refind_check_secure_boot() {
  local sb_byte=""
  local sb_var="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"

  if [[ -r "$sb_var" ]]; then
    sb_byte="$(od -An -tu1 -j4 -N1 "$sb_var" 2>/dev/null | tr -d ' \n' || true)"
  elif have_command mokutil; then
    mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled" && sb_byte="1" || sb_byte="0"
  fi

  case "$sb_byte" in
    1) _REFIND_SECURE_BOOT="enabled"  ;;
    0) _REFIND_SECURE_BOOT="disabled" ;;
    *) _REFIND_SECURE_BOOT="unknown"  ;;
  esac
  log "Secure Boot: $_REFIND_SECURE_BOOT."

  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
    warn "Secure Boot is ENABLED. Fedora's rEFInd package is not signed with the Fedora"
    warn "Secure Boot key, so refind-install will be run with --localkeys, which generates"
    warn "a local signing key and self-signs the rEFInd binaries with it."
    warn "Because this script runs refind-install non-interactively (--yes), the MOK"
    warn "enrollment prompt is skipped — you must enroll the key yourself after this run"
    warn "finishes (exact command is printed in the summary below)."
  fi
}

refind_install_package() {
  # Package name is 'rEFInd' (case-sensitive) in Fedora 44.
  log "Installing rEFInd package from Fedora repositories."
  dnf_install rEFInd || die "Failed to install rEFInd. Check repo access and try: dnf info rEFInd."

  have_command refind-install || \
    die "refind-install not found after installing rEFInd (expected from rEFInd-tools)."

  # refind-install auto-detects the ESP, copies the EFI binary, icons, and
  # filesystem drivers, and registers (and de-duplicates) the UEFI NVRAM
  # entry itself — including placing it first in BootOrder. We overlay our
  # own refind.conf afterwards for consistent, predictable settings (no
  # direct kernel scanning — GRUB is chainloaded instead, see below).
  local install_args=(--yes)
  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
    install_args+=(--localkeys)
    # --localkeys re-signs the rEFInd binaries with sbsign, which is not one
    # of rEFInd's own dependencies.
    have_command sbsign || dnf_install_best_effort sbsigntools
    have_command sbsign || die "sbsign (from sbsigntools) is required for --localkeys but could not be installed."
  fi

  log "Running: sudo refind-install ${install_args[*]}"
  run_sudo refind-install "${install_args[@]}" || \
    die "refind-install failed. Review the output above for the specific error."

  local esp_dir="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}"
  local efi_dest="${esp_dir}/${_REFIND_EFI_NAME}"
  run_sudo test -s "$efi_dest" || \
    die "refind-install completed, but ${efi_dest} is missing or empty."
  log "rEFInd installed at: $efi_dest."

  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
    record_change "Installed rEFInd with a locally generated Secure Boot key (--localkeys). MOK enrollment is still required — see summary."
  fi
}

refind_install_theme() {
  [[ "$INSTALL_REFIND_THEME" == "1" ]] || {
    log "rEFInd theme installation is disabled (INSTALL_REFIND_THEME=0)."
    return 0
  }

  have_command git || dnf_install_best_effort git
  if ! have_command git; then
    warn "git is not available; skipping rEFInd theme install."
    return 0
  fi

  log "Fetching rEFInd theme from ${REFIND_THEME_REPO}."
  if [[ -d "${REFIND_THEME_DIR}/.git" ]]; then
    git -C "$REFIND_THEME_DIR" pull --ff-only --quiet || \
      warn "Could not update theme repo at ${REFIND_THEME_DIR}; using cached copy."
  else
    rm -rf "$REFIND_THEME_DIR"
    if ! git clone --quiet "$REFIND_THEME_REPO" "$REFIND_THEME_DIR"; then
      warn "Could not clone ${REFIND_THEME_REPO}; continuing without a theme."
      return 0
    fi
  fi

  [[ -f "${REFIND_THEME_DIR}/theme.conf" ]] || {
    warn "${REFIND_THEME_DIR} has no theme.conf; not a valid rEFInd theme, skipping."
    return 0
  }

  local theme_dest="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}/themes/${REFIND_THEME_NAME}"
  backup_system_path "$theme_dest"
  run_sudo rm -rf "$theme_dest"
  run_sudo install -d -m 0755 "$(dirname "$theme_dest")"

  local tmp_theme; tmp_theme="$(mktemp -d)"
  cp -r "${REFIND_THEME_DIR}/." "${tmp_theme}/"
  rm -rf "${tmp_theme}/.git"
  # -r, not -a: the ESP is vfat, which has no concept of Unix ownership —
  # cp -a always fails trying to chown there, even as root.
  run_sudo mkdir -p "$theme_dest"
  run_sudo cp -r "${tmp_theme}/." "${theme_dest}/"
  rm -rf "$tmp_theme"

  run_sudo test -f "${theme_dest}/theme.conf" || \
    die "Theme copy to ${theme_dest} failed — theme.conf missing after copy."

  _REFIND_THEME_INSTALLED=1
  log "Installed rEFInd theme '${REFIND_THEME_NAME}' to ${theme_dest}."
  record_change "Installed rEFInd theme '${REFIND_THEME_NAME}' from ${REFIND_THEME_REPO}."
}

refind_write_conf() {
  local esp_dir="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}"
  local conf_dest="${esp_dir}/refind.conf"

  backup_system_path "$conf_dest"

  local tmp; tmp="$(mktemp)"
  cat >"$tmp" <<EOF
# rEFInd configuration — written by refind-migrate.sh on ${TIMESTAMP}
# Delete this file and re-run the script to regenerate it.

timeout ${REFIND_TIMEOUT}

# Don't scan for or directly boot Linux kernels — GRUB (kept, chainloaded)
# owns that job. rEFInd's normal boot-loader auto-scan still finds and
# offers the existing GRUB EFI binary in EFI/fedora/ as a menu entry.
scan_all_linux_kernels false

# NVRAM is managed externally via efibootmgr, not by rEFInd itself.
use_nvram false

# Default to the most recently booted entry.
default_selection lastbooted

# Let the firmware choose the graphics resolution.
resolution auto
EOF

  if [[ "$_REFIND_THEME_INSTALLED" == "1" ]]; then
    printf '\n# Theme: %s (%s)\ninclude themes/%s/theme.conf\n' \
      "$REFIND_THEME_NAME" "$REFIND_THEME_REPO" "$REFIND_THEME_NAME" >>"$tmp"
  fi

  run_sudo install -m 0644 "$tmp" "$conf_dest"
  rm -f "$tmp"
  log "Wrote rEFInd config: $conf_dest."
}

refind_locate_nvram_entry() {
  # refind-install already created (or reused) the NVRAM entry and placed it
  # first in BootOrder. This just finds its Boot#### number for our own
  # validation/removal logic, normalizes its label, and re-asserts BootOrder
  # as a defense-in-depth check (idempotent — safe if already correct).
  have_command efibootmgr || die "efibootmgr is required to validate the rEFInd NVRAM entry."

  local boot_entry boot_num
  _REFIND_BOOT_NUM=""
  while IFS= read -r boot_entry; do
    [[ "$boot_entry" =~ ^Boot([0-9A-Fa-f]{4}) ]] || continue
    boot_num="${BASH_REMATCH[1]}"
    if echo "$boot_entry" | grep -qi "refind"; then
      _REFIND_BOOT_NUM="$boot_num"
      break
    fi
  done < <(run_sudo efibootmgr 2>/dev/null || true)
  [[ -n "$_REFIND_BOOT_NUM" ]] || die "No rEFInd NVRAM entry found after refind-install. Check efibootmgr output above."

  if [[ -n "$REFIND_ENTRY_LABEL" ]]; then
    local current_label
    current_label="$(run_sudo efibootmgr 2>/dev/null | sed -n "s/^Boot${_REFIND_BOOT_NUM}\*\{0,1\}[[:space:]]*//p" | head -1)"
    if [[ "$current_label" != "$REFIND_ENTRY_LABEL" ]]; then
      run_sudo efibootmgr --bootnum "$_REFIND_BOOT_NUM" --label "$REFIND_ENTRY_LABEL" >/dev/null || \
        warn "Could not rename NVRAM entry Boot${_REFIND_BOOT_NUM} to '${REFIND_ENTRY_LABEL}'."
    fi
  fi

  local cur_order first filtered new_order
  cur_order="$(run_sudo efibootmgr 2>/dev/null | awk '/^BootOrder:/{print $2}' || true)"
  first="$(printf '%s' "$cur_order" | cut -d, -f1)"
  if [[ "${first^^}" != "${_REFIND_BOOT_NUM^^}" ]]; then
    filtered="$(printf '%s' "$cur_order" | tr ',' '\n' \
                | grep -iv "^${_REFIND_BOOT_NUM}$" | tr '\n' ',' | sed 's/,$//')"
    new_order="${_REFIND_BOOT_NUM}${filtered:+,${filtered}}"
    run_sudo efibootmgr --bootorder "$new_order" || \
      warn "Could not set BootOrder. Set manually: sudo efibootmgr --bootorder ${new_order}"
    log "Moved rEFInd to first in BootOrder (${new_order})."
  fi

  log "rEFInd NVRAM entry: Boot${_REFIND_BOOT_NUM}."
  record_change "rEFInd registered as Boot${_REFIND_BOOT_NUM}, first in BootOrder."
}

refind_locate_grub_entry() {
  # GRUB's own NVRAM entry (created originally by Anaconda/grub2-efi) is left
  # completely alone — refind-install only adds/reorders its own entry. Find
  # it so we can point at it as a concrete fallback in the summary.
  _GRUB_BOOT_NUM=""
  local boot_entry boot_num
  while IFS= read -r boot_entry; do
    [[ "$boot_entry" =~ ^Boot([0-9A-Fa-f]{4}) ]] || continue
    boot_num="${BASH_REMATCH[1]}"
    [[ "${boot_num^^}" == "${_REFIND_BOOT_NUM^^}" ]] && continue
    if echo "$boot_entry" | grep -qiE '\\EFI\\fedora\\'; then
      _GRUB_BOOT_NUM="$boot_num"
      break
    fi
  done < <(run_sudo efibootmgr -v 2>/dev/null || true)

  if [[ -n "$_GRUB_BOOT_NUM" ]]; then
    log "Existing GRUB NVRAM entry kept as fallback: Boot${_GRUB_BOOT_NUM}."
  else
    warn "No separate GRUB NVRAM entry found — firmware boot menu will only offer rEFInd."
  fi
}

refind_validate() {
  local errors=0
  log "Validating rEFInd installation…"

  local efi_bin="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}/${_REFIND_EFI_NAME}"
  if run_sudo test -s "$efi_bin"; then
    log "  [✓] EFI binary present: $efi_bin"
  else
    warn "  [✗] EFI binary missing or empty: $efi_bin"
    errors=$(( errors + 1 ))
  fi

  local conf="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}/refind.conf"
  if run_sudo test -f "$conf"; then
    log "  [✓] refind.conf: $conf"
  else
    warn "  [✗] refind.conf missing: $conf"
    errors=$(( errors + 1 ))
  fi

  if [[ -n "$_REFIND_BOOT_NUM" ]] && \
     run_sudo efibootmgr 2>/dev/null | grep -q "Boot${_REFIND_BOOT_NUM}"; then
    log "  [✓] NVRAM entry Boot${_REFIND_BOOT_NUM} present"
  else
    warn "  [✗] NVRAM entry Boot${_REFIND_BOOT_NUM:-???} not found"
    errors=$(( errors + 1 ))
  fi

  local first
  first="$(run_sudo efibootmgr 2>/dev/null | awk '/^BootOrder:/{split($2,a,","); print a[1]}' || true)"
  if [[ "${first^^}" == "${_REFIND_BOOT_NUM^^}" ]]; then
    log "  [✓] rEFInd is first in BootOrder"
  else
    warn "  [✗] rEFInd (Boot${_REFIND_BOOT_NUM}) is not first in BootOrder (first: Boot${first})"
    errors=$(( errors + 1 ))
  fi

  local grub_efi_name
  case "$_REFIND_ARCH" in
    x64)  grub_efi_name="grubx64.efi"  ;;
    aa64) grub_efi_name="grubaa64.efi" ;;
    ia32) grub_efi_name="grubia32.efi" ;;
  esac
  local grub_efi="${_REFIND_ESP}/EFI/fedora/${grub_efi_name}"
  if run_sudo test -s "$grub_efi"; then
    log "  [✓] GRUB EFI binary present for chainloading: $grub_efi"
  else
    warn "  [✗] GRUB EFI binary not found: $grub_efi — rEFInd will have nothing to chainload."
    errors=$(( errors + 1 ))
  fi

  (( errors == 0 )) || die "rEFInd validation failed ($errors error(s)). Fix the warnings above and re-run."
  log "rEFInd validation passed."
}

grub_upsert_default() {
  local key="$1"
  local value="$2"
  local path="/etc/default/grub"
  local tmp; tmp="$(mktemp)"

  awk -v key="$key" -v value="$value" '
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

refind_configure_grub_boot() {
  local grub_default="/etc/default/grub"
  [[ -f "$grub_default" ]] || {
    warn "$grub_default not found; skipping GRUB timeout configuration."
    return 0
  }

  log "Configuring GRUB for instant, silent boot (rEFInd chainloads it directly)."
  backup_system_path "$grub_default"

  grub_upsert_default GRUB_TIMEOUT 0
  grub_upsert_default GRUB_TIMEOUT_STYLE hidden

  if have_command grub2-mkconfig; then
    run_sudo grub2-mkconfig -o /boot/grub2/grub.cfg || \
      warn "grub2-mkconfig failed; GRUB timeout change may not take effect until it's regenerated."
    record_change "Set GRUB_TIMEOUT=0 (hidden menu) and regenerated grub.cfg for instant boot."
  else
    warn "grub2-mkconfig not found; GRUB_TIMEOUT was set in $grub_default but grub.cfg was not regenerated."
  fi
}

refind_print_summary() {
  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_CYAN" "$COLOR_RESET"
  printf '%s  rEFInd Boot Manager Summary%s\n' "$COLOR_CYAN" "$COLOR_RESET"
  printf '%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_CYAN" "$COLOR_RESET"
  printf '\n'
  printf '  EFI System Partition : %s\n'                "$_REFIND_ESP"
  printf '  rEFInd EFI binary    : %s/%s/%s\n'           "$_REFIND_ESP" "$REFIND_ESP_SUBDIR" "$_REFIND_EFI_NAME"
  printf '  rEFInd config        : %s/%s/refind.conf\n'  "$_REFIND_ESP" "$REFIND_ESP_SUBDIR"
  if [[ "$_REFIND_THEME_INSTALLED" == "1" ]]; then
    printf '  rEFInd theme         : %s (%s/%s/themes/%s)\n' \
      "$REFIND_THEME_NAME" "$_REFIND_ESP" "$REFIND_ESP_SUBDIR" "$REFIND_THEME_NAME"
  else
    printf '  rEFInd theme         : none (default look)\n'
  fi
  printf '  Boots into           : existing GRUB installation (chainloaded, unchanged)\n'
  printf '  GRUB menu            : hidden, 0s timeout (instant boot)\n'
  printf '  Secure Boot state    : %s\n'                 "$_REFIND_SECURE_BOOT"
  printf '  NVRAM entry          : Boot%s  (%s)\n'        "${_REFIND_BOOT_NUM:-???}" "$REFIND_ENTRY_LABEL"
  if [[ -n "$_GRUB_BOOT_NUM" ]]; then
    printf '  GRUB NVRAM entry     : Boot%s  (kept as-is, untouched fallback)\n' "$_GRUB_BOOT_NUM"
  fi
  printf '\n'
  printf '  %sCurrent UEFI boot order:%s\n' "$COLOR_BOLD" "$COLOR_RESET"
  run_sudo efibootmgr 2>/dev/null | grep -E '^Boot[0-9A-Fa-f]{4}' | sed 's/^/    /' || true
  printf '\n'
  printf '  %sRecovery (if rEFInd does not boot):%s\n' "$COLOR_YELLOW" "$COLOR_RESET"
  printf '  GRUB was NOT modified or removed — only rEFInd'"'"'s own NVRAM entry was\n'
  printf '  added/reordered.\n'
  if [[ -n "$_GRUB_BOOT_NUM" ]]; then
    printf '  1. At the firmware boot menu (usually F12, F11, Esc, or Del at power-on),\n'
    printf '     select Boot%s directly — this bypasses rEFInd entirely and boots\n' "$_GRUB_BOOT_NUM"
    printf '     straight into GRUB.\n'
    printf '  2. To make that permanent:\n'
    printf '       sudo efibootmgr --bootorder %s\n' "$_GRUB_BOOT_NUM"
  else
    printf '  1. At the firmware boot menu (usually F12, F11, Esc, or Del at power-on),\n'
    printf '     look for a "Fedora" or similar entry and select it directly to bypass\n'
    printf '     rEFInd and boot straight into GRUB.\n'
  fi
  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
    printf '\n  %sSecure Boot — action required before rEFInd will start:%s\n' "$COLOR_YELLOW" "$COLOR_RESET"
    printf '  refind-install was run with --localkeys, which generated a local signing\n'
    printf '  key and self-signed the rEFInd binaries. That key is NOT yet trusted by\n'
    printf '  your firmware. Option A (recommended) — enroll it as a MOK:\n'
    printf '    sudo mokutil --import /etc/refind.d/keys/refind_local.cer\n'
    printf '    (you will set a one-time password, then reboot and enroll it at the\n'
    printf '     blue MokManager screen using that password)\n'
    printf '  Option B — disable Secure Boot in your UEFI firmware settings instead.\n'
  fi
  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n' "$COLOR_CYAN" "$COLOR_RESET"
}

install_refind() {
  warn "rEFInd will be installed as the primary UEFI boot manager."
  warn "It chainloads your existing GRUB installation — GRUB itself is not removed"
  warn "or modified beyond setting its timeout to 0 for an instant, silent boot."
  if [[ "$ASSUME_YES" != "1" ]]; then
    ask_yes_no "Continue with rEFInd installation?" y || {
      log "rEFInd installation cancelled by user."
      return 0
    }
  fi

  refind_check_uefi
  refind_check_deps
  refind_detect_esp
  refind_detect_arch
  refind_check_secure_boot

  refind_install_package
  refind_install_theme
  refind_locate_nvram_entry
  refind_locate_grub_entry
  refind_write_conf
  refind_validate
  refind_configure_grub_boot

  refind_print_summary
  record_change "Installed rEFInd as the primary UEFI boot manager, chainloading GRUB."
}

print_summary() {
  local item

  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  rEFInd migration complete%s\n' "$COLOR_GREEN" "$COLOR_RESET"
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

  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n' "$COLOR_GREEN" "$COLOR_RESET"
}

main() {
  require_fedora
  prepare_runtime
  install_refind
  print_summary
}

main "$@"
