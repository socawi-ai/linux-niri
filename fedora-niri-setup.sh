#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_REPO_URL="${CONFIG_REPO_URL:-https://github.com/socawi-ai/linux-niri}"
CONFIG_REPO_DIR_WAS_SET=0
CONFIG_SOURCE_DIR_WAS_SET=0
USER_BACKUP_ROOT_WAS_SET=0
MCMOJAVE_CURSORS_DIR_WAS_SET=0
SLEEK_GRUB_THEME_DIR_WAS_SET=0
[[ -n "${CONFIG_REPO_DIR+x}" ]] && CONFIG_REPO_DIR_WAS_SET=1
[[ -n "${CONFIG_SOURCE_DIR+x}" ]] && CONFIG_SOURCE_DIR_WAS_SET=1
[[ -n "${USER_BACKUP_ROOT+x}" ]] && USER_BACKUP_ROOT_WAS_SET=1
[[ -n "${MCMOJAVE_CURSORS_DIR+x}" ]] && MCMOJAVE_CURSORS_DIR_WAS_SET=1
[[ -n "${SLEEK_GRUB_THEME_DIR+x}" ]] && SLEEK_GRUB_THEME_DIR_WAS_SET=1
CONFIG_REPO_BRANCH="${CONFIG_REPO_BRANCH:-main}"
CONFIG_REPO_DIR="${CONFIG_REPO_DIR:-$HOME/.cache/fedora-niri-setup/linux-niri}"
CONFIG_SOURCE_DIR="${CONFIG_SOURCE_DIR:-}"
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
ASSUME_YES="${ASSUME_YES:-0}"
EXTRA_FEDORA_PACKAGES="${EXTRA_FEDORA_PACKAGES:-}"
DNF_SKIP_UNAVAILABLE="${DNF_SKIP_UNAVAILABLE:-1}"

ENABLE_NOCTALIA_COPR="${ENABLE_NOCTALIA_COPR:-1}"
ENABLE_GREETD="${ENABLE_GREETD:-1}"
ENABLE_FEDORA_THIRD_PARTY_REPOS="${ENABLE_FEDORA_THIRD_PARTY_REPOS:-1}"
ENABLE_RPMFUSION="${ENABLE_RPMFUSION:-1}"
INSTALL_STEAM="${INSTALL_STEAM:-1}"
INSTALL_VSCODE="${INSTALL_VSCODE:-1}"
INSTALL_MCMOJAVE_CURSORS="${INSTALL_MCMOJAVE_CURSORS:-1}"
INSTALL_NAUTILUS_OPEN_ANY_TERMINAL="${INSTALL_NAUTILUS_OPEN_ANY_TERMINAL:-1}"
INSTALL_POLARIS="${INSTALL_POLARIS:-1}"
SETUP_POLARIS_HOST="${SETUP_POLARIS_HOST:-1}"
ENABLE_POLARIS_AUTOSTART="${ENABLE_POLARIS_AUTOSTART:-1}"
ENABLE_POLARIS_LINGER="${ENABLE_POLARIS_LINGER:-1}"
CONFIGURE_PLYMOUTH="${CONFIGURE_PLYMOUTH:-1}"
CONFIGURE_GRUB_THEME="${CONFIGURE_GRUB_THEME:-1}"
DISABLE_CONFLICTING_DISPLAY_MANAGERS="${DISABLE_CONFLICTING_DISPLAY_MANAGERS:-1}"
NOCTALIA_COPR="${NOCTALIA_COPR:-lionheartp/Hyprland}"
NOCTALIA_PACKAGE="${NOCTALIA_PACKAGE:-noctalia-git}"
NOCTALIA_GREETER_PACKAGE="${NOCTALIA_GREETER_PACKAGE:-noctalia-greeter}"
NAUTILUS_OPEN_ANY_TERMINAL_COPR="${NAUTILUS_OPEN_ANY_TERMINAL_COPR:-monkeygold/nautilus-open-any-terminal}"
NAUTILUS_TERMINAL="${NAUTILUS_TERMINAL:-alacritty}"
MCMOJAVE_CURSORS_REPO="${MCMOJAVE_CURSORS_REPO:-https://github.com/vinceliuice/McMojave-cursors}"
MCMOJAVE_CURSORS_DIR="${MCMOJAVE_CURSORS_DIR:-$HOME/.cache/fedora-niri-setup/McMojave-cursors}"
MCMOJAVE_CURSOR_THEME="${MCMOJAVE_CURSOR_THEME:-McMojave-cursors}"
POLARIS_BASE_URL="${POLARIS_BASE_URL:-https://github.com/papi-ux/polaris/releases/latest/download}"
SLEEK_GRUB_THEME_REPO="${SLEEK_GRUB_THEME_REPO:-$CONFIG_REPO_URL}"
SLEEK_GRUB_THEME_BRANCH="${SLEEK_GRUB_THEME_BRANCH:-$CONFIG_REPO_BRANCH}"
SLEEK_GRUB_THEME_DIR="${SLEEK_GRUB_THEME_DIR:-$HOME/.cache/fedora-niri-setup/linux-niri-grub-theme}"
SLEEK_GRUB_THEME_SOURCE_SUBDIR="${SLEEK_GRUB_THEME_SOURCE_SUBDIR:-grub/sleek-dark}"
SLEEK_GRUB_THEME_TARGET="${SLEEK_GRUB_THEME_TARGET:-/boot/grub2/themes/sleek}"
GRUB_GFXMODE="${GRUB_GFXMODE:-3440x1440,2560x1440,1920x1080,auto}"
GRUB_TIMEOUT_SECONDS="${GRUB_TIMEOUT_SECONDS:-10}"
GRUB_CONFIG_FILE="${GRUB_CONFIG_FILE:-/etc/default/grub}"
GRUB_MKCONFIG_OUTPUT="${GRUB_MKCONFIG_OUTPUT:-/boot/grub2/grub.cfg}"
NOCTALIA_CONFIG_FILE="${NOCTALIA_CONFIG_FILE:-settings.toml}"
NOCTALIA_CONFIG_RELATIVE_DIR="${NOCTALIA_CONFIG_RELATIVE_DIR:-.local/state/noctalia}"
NOCTALIA_WALLPAPER_FILE="${NOCTALIA_WALLPAPER_FILE:-13.png}"
NOCTALIA_WALLPAPER_MONITORS="${NOCTALIA_WALLPAPER_MONITORS:-}"
GREETD_USER="${GREETD_USER:-greeter}"
NOCTALIA_GREETER_SESSION_BIN="${NOCTALIA_GREETER_SESSION_BIN:-}"

# ─── rEFInd UEFI bootloader ───────────────────────────────────────────────────
# Set INSTALL_REFIND=0 to skip entirely.  REFIND_REMOVE_GRUB=0 keeps GRUB after
# rEFInd is validated (useful if you want to verify first, then re-run).
INSTALL_REFIND="${INSTALL_REFIND:-1}"
REFIND_REMOVE_GRUB="${REFIND_REMOVE_GRUB:-1}"
REFIND_TIMEOUT="${REFIND_TIMEOUT:-5}"
REFIND_ENTRY_LABEL="${REFIND_ENTRY_LABEL:-Fedora Linux}"
REFIND_ESP_SUBDIR="${REFIND_ESP_SUBDIR:-EFI/refind}"
REFIND_RECOVERY_DIR="${REFIND_RECOVERY_DIR:-/var/backups/bootloader-migration}"

# Runtime state — populated by rEFInd preflight; not user-configurable.
_REFIND_ESP=""
_REFIND_ESP_DISK=""
_REFIND_ESP_PARTNUM=""
_REFIND_ARCH=""
_REFIND_EFI_NAME=""
_REFIND_SECURE_BOOT=""
_REFIND_BOOT_NUM=""

XKB_LAYOUT="${XKB_LAYOUT:-se}"
GTK_COLOR_SCHEME="${GTK_COLOR_SCHEME:-prefer-dark}"
GTK_THEME_NAME="${GTK_THEME_NAME:-Adwaita-dark}"
GTK_APPLICATION_PREFER_DARK="${GTK_APPLICATION_PREFER_DARK:-1}"
GTK_CURSOR_THEME="${GTK_CURSOR_THEME:-$MCMOJAVE_CURSOR_THEME}"
XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
WALLPAPER_PARENT_DIR="${WALLPAPER_PARENT_DIR:-}"
WALLPAPER_SUBDIR="${WALLPAPER_SUBDIR:-wallpapers}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_FILE:-$HOME/fedora-niri-setup-$TIMESTAMP.log}"
USER_BACKUP_ROOT="${USER_BACKUP_ROOT:-$HOME/.local/share/fedora-niri-setup/backups/$TIMESTAMP}"
SYSTEM_BACKUP_ROOT="${SYSTEM_BACKUP_ROOT:-/var/backups/fedora-niri-setup/$TIMESTAMP}"

TARGET_HOME="$HOME"
DNF_BIN=""
DNF_SKIP_UNAVAILABLE_SUPPORTED=""
STEP_COUNT=0

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

TOTAL_SECTIONS=10

declare -a CHANGES=()
declare -a WARNINGS=()
declare -a USER_BACKUPS=()
declare -a SYSTEM_BACKUPS=()

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'die "Setup failed on or near line $LINENO. Review $LOG_FILE, fix the reported problem, then re-run the script."' ERR

print_banner() {
  printf '\n'
  printf '%s  ╭──────────────────────────────────────────────────────╮%s\n' "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  │                                                      │%s\n' "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  │  %sFedora Niri Setup%s                                   │%s\n' "$COLOR_BLUE" "$COLOR_BOLD" "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  │  %sNiri desktop installer for Fedora Linux%s             │%s\n' "$COLOR_BLUE" "$COLOR_DIM" "$COLOR_BLUE" "$COLOR_RESET"
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

package_installed() {
  rpm -q "$1" >/dev/null 2>&1
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

resolve_target_user() {
  if [[ "$ASSUME_YES" != "1" ]]; then
    TARGET_USER="$(ask_value "Target username for user configs" "$TARGET_USER")"
  fi

  [[ "$TARGET_USER" != "root" ]] || die "Refusing to install user desktop config for root."
  getent passwd "$TARGET_USER" >/dev/null || die "User '$TARGET_USER' does not exist."

  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$TARGET_HOME" ]] || die "Could not determine home directory for $TARGET_USER."

  if [[ "$CONFIG_REPO_DIR_WAS_SET" == "0" ]]; then
    CONFIG_REPO_DIR="$TARGET_HOME/.cache/fedora-niri-setup/linux-niri"
  fi

  if [[ "$USER_BACKUP_ROOT_WAS_SET" == "0" ]]; then
    USER_BACKUP_ROOT="$TARGET_HOME/.local/share/fedora-niri-setup/backups/$TIMESTAMP"
  fi

  if [[ "$CONFIG_SOURCE_DIR_WAS_SET" == "0" ]]; then
    CONFIG_SOURCE_DIR="$CONFIG_REPO_DIR"
  fi

  if [[ "$MCMOJAVE_CURSORS_DIR_WAS_SET" == "0" ]]; then
    MCMOJAVE_CURSORS_DIR="$TARGET_HOME/.cache/fedora-niri-setup/McMojave-cursors"
  fi

  if [[ "$SLEEK_GRUB_THEME_DIR_WAS_SET" == "0" ]]; then
    SLEEK_GRUB_THEME_DIR="$TARGET_HOME/.cache/fedora-niri-setup/linux-niri-grub-theme"
  fi

  log "Target user: $TARGET_USER"
  log "Target home: $TARGET_HOME"
  log "Config repo: $CONFIG_REPO_URL"
  log "Config source: $CONFIG_SOURCE_DIR"
}

prepare_runtime() {
  run_as_user mkdir -p "$USER_BACKUP_ROOT"
  run_sudo install -d -m 0755 "$SYSTEM_BACKUP_ROOT"
  run_sudo -v
  log "Log file: $LOG_FILE"
  log "User backups: $USER_BACKUP_ROOT"
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

backup_user_path() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  if already_backed_up "$path" "${USER_BACKUPS[@]}"; then
    return 0
  fi

  local dest="$USER_BACKUP_ROOT$path"
  run_as_user mkdir -p "$(dirname "$dest")"
  run_as_user cp -a "$path" "$dest"
  USER_BACKUPS+=("$path")
  log "Backed up user path $path -> $dest"
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

replace_user_path_with_dir() {
  local src="$1"
  local dest="$2"
  [[ -d "$src" ]] || die "Expected directory $src."

  case "$dest" in
    "$TARGET_HOME"/*) ;;
    *) die "Refusing to replace path outside target home: $dest" ;;
  esac

  backup_user_path "$dest"
  run_as_user rm -rf -- "$dest"
  run_as_user mkdir -p "$(dirname "$dest")"
  run_as_user cp -a "$src" "$dest"
  record_change "Installed $(basename "$dest") config to $dest."
}

safe_rm_rf() {
  local path="$1"
  [[ -n "$path" && "$path" != "/" ]] || die "Refusing to remove unsafe path: $path"

  case "$path" in
    "$TARGET_HOME"/*)
      run_as_user rm -rf -- "$path"
      ;;
    /tmp/*|/var/tmp/*|/private/tmp/*|/private/var/tmp/*)
      run_as_user rm -rf -- "$path"
      ;;
    *)
      die "Refusing to remove $path because it is outside the expected user or temporary directories."
      ;;
  esac
}

write_user_file() {
  local path="$1"
  local mode="${2:-0644}"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  backup_user_path "$path"
  chmod 0644 "$tmp"
  run_as_user install -D -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}

replace_user_file() {
  local src="$1"
  local dest="$2"
  [[ -f "$src" ]] || die "Expected file $src."

  case "$dest" in
    "$TARGET_HOME"/*) ;;
    *) die "Refusing to replace path outside target home: $dest" ;;
  esac

  backup_user_path "$dest"
  run_as_user rm -f "$dest"
  run_as_user mkdir -p "$(dirname "$dest")"
  run_as_user cp -a "$src" "$dest"
  record_change "Installed file $dest from $src."
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

toml_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
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

enable_copr_repo() {
  local copr="$1"
  local label="${2:-$copr}"
  local repo_owner="${copr%%/*}"
  local repo_name="${copr#*/}"
  local repo_glob="/etc/yum.repos.d/*${repo_owner}*${repo_name}*.repo"

  dnf_install_best_effort dnf-plugins-core

  if compgen -G "$repo_glob" >/dev/null; then
    log "COPR $copr appears to be enabled."
    return 0
  fi

  log "Enabling COPR $copr for $label."
  if run_sudo "$DNF_BIN" copr enable -y "$copr"; then
    record_change "Enabled COPR $copr."
  else
    warn "Could not enable COPR $copr."
    return 1
  fi
}

install_fedora_packages() {
  local packages=(
    dnf-plugins-core
    gcc
    gcc-c++
    make
    automake
    autoconf
    pkgconf-pkg-config
    redhat-rpm-config
    rpm-build
    curl
    git
    gh
    tar
    xz
    fedora-workstation-repositories
    grubby
    grub2-tools
    efibootmgr
    plymouth
    plymouth-plugin-spinner
    plymouth-system-theme
    niri
    greetd
    greetd-selinux
    alacritty
    jetbrains-mono-fonts
    fish
    firefox
    xwayland-satellite
    nautilus
    gnome-software
    xdg-user-dirs
    xdg-utils
    file-roller
    loupe
    gnome-text-editor
    gnome-calculator
    gnome-disk-utility
    gnome-system-monitor
    xdg-desktop-portal
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
    dbus
    dconf
    libsecret
    avahi
    nss-mdns
    gvfs
    gvfs-smb
    gvfs-mtp
    gvfs-afc
    gtk3
    gtk4
    qt5-qtwayland
    qt6-qtwayland
    qt6-qtbase
    qt6-qtdeclarative
    pipewire
    wireplumber
    pipewire-pulseaudio
    pipewire-alsa
    pipewire-jack-audio-connection-kit
    pavucontrol
  )

  if [[ -n "$EXTRA_FEDORA_PACKAGES" ]]; then
    local extra_packages=()
    read -r -a extra_packages <<<"$EXTRA_FEDORA_PACKAGES"
    packages+=("${extra_packages[@]}")
  fi

  log "Installing Fedora packages with $DNF_BIN."
  dnf_install_best_effort "${packages[@]}"
  record_change "Installed or attempted Fedora packages for a basic Niri desktop."
}

enable_fedora_third_party_repos() {
  [[ "$ENABLE_FEDORA_THIRD_PARTY_REPOS" == "1" ]] || {
    log "Fedora third-party repository enablement is disabled."
    return 0
  }

  dnf_install_best_effort fedora-workstation-repositories

  if have_command fedora-third-party; then
    log "Enabling Fedora third-party repositories."
    run_sudo fedora-third-party enable || warn "fedora-third-party enable failed."
    record_change "Enabled Fedora third-party repositories."
  else
    warn "fedora-third-party command is not available after installing fedora-workstation-repositories."
  fi
}

enable_rpmfusion() {
  [[ "$ENABLE_RPMFUSION" == "1" ]] || {
    log "RPM Fusion enablement is disabled."
    return 0
  }

  local fedora_version
  fedora_version="$(rpm -E %fedora)"

  log "Enabling RPM Fusion free and nonfree repositories."
  dnf_install_best_effort \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"

  run_sudo "$DNF_BIN" makecache -y || warn "RPM Fusion makecache failed."
  record_change "Enabled RPM Fusion free and nonfree repositories."
}

install_steam() {
  [[ "$INSTALL_STEAM" == "1" ]] || {
    log "Steam installation is disabled."
    return 0
  }

  enable_fedora_third_party_repos
  enable_rpmfusion

  log "Installing Steam from RPM Fusion."
  if dnf_install_optional steam; then
    record_change "Installed Steam from RPM Fusion."
  fi
}

set_systemd_user_service() {
  local service="$1"
  local user_id
  user_id="$(id -u "$TARGET_USER")"
  if [[ -d "/run/user/$user_id" ]]; then
    if run_as_user env XDG_RUNTIME_DIR="/run/user/$user_id" systemctl --user enable --now "$service"; then
      return 0
    fi
    warn "Could not enable and start user service $service now."
  else
    if run_as_user systemctl --user enable "$service"; then
      warn "Enabled $service for user autostart, but could not start it now because /run/user/$user_id does not exist."
      return 0
    fi
    warn "Could not enable user service $service."
  fi

  return 1
}

configure_polaris_autostart() {
  [[ "$ENABLE_POLARIS_AUTOSTART" == "1" ]] || {
    log "Polaris autostart is disabled."
    return 0
  }

  if [[ "$ENABLE_POLARIS_LINGER" == "1" ]]; then
    run_sudo loginctl enable-linger "$TARGET_USER" || warn "Could not enable linger for $TARGET_USER."
  fi

  if set_systemd_user_service polaris.service; then
    record_change "Enabled Polaris user service autostart."
  fi
}

find_sleek_dark_grub_theme_dir() {
  local configured_dir="$SLEEK_GRUB_THEME_DIR/$SLEEK_GRUB_THEME_SOURCE_SUBDIR"
  local theme_file
  local lower_theme_file
  local fallback_dir=""

  if [[ -f "$configured_dir/theme.txt" ]]; then
    printf '%s\n' "$configured_dir"
    return 0
  fi

  while IFS= read -r theme_file; do
    [[ -n "$theme_file" ]] || continue
    lower_theme_file="${theme_file,,}"
    if [[ "$lower_theme_file" == *dark* ]]; then
      dirname "$theme_file"
      return 0
    fi
    [[ -n "$fallback_dir" ]] || fallback_dir="$(dirname "$theme_file")"
  done < <(find "$SLEEK_GRUB_THEME_DIR" -maxdepth 4 -type f -name theme.txt -print 2>/dev/null | sort)

  [[ -n "$fallback_dir" ]] || return 1
  printf '%s\n' "$fallback_dir"
}

resolve_grub_theme_payload_dir() {
  local source_dir="$1"

  if [[ -f "$source_dir/theme.txt" ]]; then
    printf '%s\n' "$source_dir"
    return 0
  fi

  if [[ -f "$source_dir/sleek/theme.txt" ]]; then
    printf '%s\n' "$source_dir/sleek"
    return 0
  fi

  return 1
}

install_grub_theme() {
  [[ "$CONFIGURE_GRUB_THEME" == "1" ]] || {
    log "GRUB theme configuration is disabled."
    return 0
  }
  if [[ "$INSTALL_REFIND" == "1" ]]; then
    log "Skipping GRUB theme installation — rEFInd will replace GRUB."
    return 0
  fi

  clone_or_update_git_repo "$SLEEK_GRUB_THEME_REPO" "$SLEEK_GRUB_THEME_DIR" "$SLEEK_GRUB_THEME_BRANCH"

  local source_dir
  local payload_dir
  if ! source_dir="$(find_sleek_dark_grub_theme_dir)"; then
    warn "No Sleek GRUB theme.txt file was found in $SLEEK_GRUB_THEME_DIR."
    return 0
  fi

  if ! payload_dir="$(resolve_grub_theme_payload_dir "$source_dir")"; then
    warn "Sleek GRUB theme source $source_dir does not contain theme.txt or sleek/theme.txt."
    return 0
  fi

  case "$SLEEK_GRUB_THEME_TARGET" in
    /boot/grub2/themes/*|/boot/grub/themes/*) ;;
    *) die "Refusing to install GRUB theme outside a GRUB themes directory: $SLEEK_GRUB_THEME_TARGET" ;;
  esac

  backup_system_path "$SLEEK_GRUB_THEME_TARGET"
  run_sudo rm -rf -- "$SLEEK_GRUB_THEME_TARGET"
  run_sudo install -d -m 0755 "$SLEEK_GRUB_THEME_TARGET"

  local theme_archive
  theme_archive="$(mktemp)"
  tar -C "$payload_dir" -cf "$theme_archive" .
  run_sudo tar -C "$SLEEK_GRUB_THEME_TARGET" -xf "$theme_archive"
  run_sudo chown -R root:root "$SLEEK_GRUB_THEME_TARGET"
  rm -f "$theme_archive"

  if ! run_sudo test -f "$SLEEK_GRUB_THEME_TARGET/theme.txt"; then
    warn "Sleek GRUB theme copy finished, but $SLEEK_GRUB_THEME_TARGET/theme.txt is missing."
    run_sudo find "$SLEEK_GRUB_THEME_TARGET" -maxdepth 2 -type f -print 2>/dev/null || true
    return 0
  fi

  record_change "Installed Sleek GRUB theme from $payload_dir to $SLEEK_GRUB_THEME_TARGET."
}

upsert_grub_default() {
  local key="$1"
  local value="$2"
  local path="$GRUB_CONFIG_FILE"
  local tmp

  [[ -f "$path" ]] || {
    warn "$path does not exist; skipping GRUB default update for $key."
    return 0
  }

  backup_system_path "$path"
  tmp="$(mktemp)"

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

regenerate_grub_config() {
  if [[ "$INSTALL_REFIND" == "1" ]]; then
    log "Skipping grub2-mkconfig — rEFInd will replace GRUB."
    return 0
  fi
  if have_command grub2-mkconfig; then
    run_sudo grub2-mkconfig -o "$GRUB_MKCONFIG_OUTPUT"
    record_change "Regenerated GRUB config at $GRUB_MKCONFIG_OUTPUT."
  else
    warn "grub2-mkconfig was not found; GRUB config was not regenerated."
  fi
}

verify_grub_theme_config() {
  [[ "$CONFIGURE_GRUB_THEME" == "1" ]] || return 0

  if ! run_sudo test -f "$SLEEK_GRUB_THEME_TARGET/theme.txt"; then
    warn "GRUB theme file is missing after install: $SLEEK_GRUB_THEME_TARGET/theme.txt"
    return 0
  fi

  if run_sudo test -f "$GRUB_CONFIG_FILE" && ! run_sudo grep -Fq "GRUB_THEME=\"$SLEEK_GRUB_THEME_TARGET/theme.txt\"" "$GRUB_CONFIG_FILE"; then
    warn "$GRUB_CONFIG_FILE does not contain the expected GRUB_THEME path."
  fi

  if run_sudo test -f "$GRUB_MKCONFIG_OUTPUT" && ! run_sudo grep -Fq "$(basename "$SLEEK_GRUB_THEME_TARGET")/theme.txt" "$GRUB_MKCONFIG_OUTPUT"; then
    warn "$GRUB_MKCONFIG_OUTPUT does not reference the Sleek theme. Re-run grub2-mkconfig manually and check GRUB errors."
  fi
}

configure_plymouth_and_grub() {
  [[ "$CONFIGURE_PLYMOUTH" == "1" || "$CONFIGURE_GRUB_THEME" == "1" ]] || return 0

  if [[ "$CONFIGURE_PLYMOUTH" == "1" ]]; then
    log "Installing and configuring Plymouth spinner theme."
    dnf_install_best_effort plymouth plymouth-plugin-spinner plymouth-system-theme grubby

    if have_command plymouth-set-default-theme; then
      run_sudo plymouth-set-default-theme -R spinner
      record_change "Configured Plymouth spinner theme."
    else
      warn "plymouth-set-default-theme was not found; Plymouth theme was not changed."
    fi

    if have_command grubby; then
      run_sudo grubby --update-kernel=ALL --args="rhgb quiet splash" || warn "Could not add Plymouth kernel arguments with grubby."
    else
      warn "grubby was not found; kernel arguments were not updated."
    fi
  fi

  install_grub_theme

  upsert_grub_default GRUB_TIMEOUT "\"$GRUB_TIMEOUT_SECONDS\""
  upsert_grub_default GRUB_TIMEOUT_STYLE "\"menu\""
  upsert_grub_default GRUB_GFXMODE "\"$GRUB_GFXMODE\""
  upsert_grub_default GRUB_TERMINAL_OUTPUT "\"gfxterm\""
  if [[ "$CONFIGURE_GRUB_THEME" == "1" ]] && run_sudo test -f "$SLEEK_GRUB_THEME_TARGET/theme.txt"; then
    upsert_grub_default GRUB_THEME "\"$SLEEK_GRUB_THEME_TARGET/theme.txt\""
  fi

  regenerate_grub_config
  verify_grub_theme_config
  record_change "Configured GRUB timeout to $GRUB_TIMEOUT_SECONDS seconds."
}

install_vscode() {
  [[ "$INSTALL_VSCODE" == "1" ]] || {
    log "VS Code installation is disabled."
    return 0
  }

  log "Configuring Microsoft VS Code repository."
  if ! run_sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc; then
    warn "Could not import Microsoft package signing key; skipping VS Code."
    return 0
  fi

  write_system_file /etc/yum.repos.d/vscode.repo 0644 <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

  if dnf_install_optional code; then
    record_change "Installed Visual Studio Code."
  fi
}

clone_or_update_git_repo() {
  local repo_url="$1"
  local repo_dir="$2"
  local branch="${3:-}"

  run_as_user mkdir -p "$(dirname "$repo_dir")"

  if [[ -d "$repo_dir/.git" ]]; then
    local current_url
    current_url="$(run_as_user git -C "$repo_dir" config --get remote.origin.url || true)"
    if [[ "$current_url" != "$repo_url" ]]; then
      warn "$repo_dir has origin $current_url, not $repo_url. Backing it up and cloning fresh."
      backup_user_path "$repo_dir"
      safe_rm_rf "$repo_dir"
      if [[ -n "$branch" ]]; then
        run_as_user git clone --branch "$branch" "$repo_url" "$repo_dir"
      else
        run_as_user git clone "$repo_url" "$repo_dir"
      fi
    else
      log "Updating repository at $repo_dir."
      run_as_user git -C "$repo_dir" fetch --prune
      if [[ -n "$branch" ]]; then
        run_as_user git -C "$repo_dir" checkout -f "$branch"
        run_as_user git -C "$repo_dir" reset --hard "origin/$branch"
      else
        run_as_user git -C "$repo_dir" pull --ff-only
      fi
    fi
  elif [[ -e "$repo_dir" ]]; then
    warn "$repo_dir exists but is not a git repository. Backing it up and cloning fresh."
    backup_user_path "$repo_dir"
    safe_rm_rf "$repo_dir"
    if [[ -n "$branch" ]]; then
      run_as_user git clone --branch "$branch" "$repo_url" "$repo_dir"
    else
      run_as_user git clone "$repo_url" "$repo_dir"
    fi
  else
    log "Cloning $repo_url to $repo_dir."
    if [[ -n "$branch" ]]; then
      run_as_user git clone --branch "$branch" "$repo_url" "$repo_dir"
    else
      run_as_user git clone "$repo_url" "$repo_dir"
    fi
  fi
}

install_mcmojave_cursors() {
  [[ "$INSTALL_MCMOJAVE_CURSORS" == "1" ]] || {
    log "McMojave cursor installation is disabled."
    return 0
  }

  clone_or_update_git_repo "$MCMOJAVE_CURSORS_REPO" "$MCMOJAVE_CURSORS_DIR"

  local theme_dir="$MCMOJAVE_CURSORS_DIR/dist"
  if [[ ! -d "$theme_dir" || ! -f "$theme_dir/index.theme" ]]; then
    warn "No installable cursor theme found at $theme_dir; skipping McMojave cursor install."
    return 0
  fi

  run_as_user mkdir -p "$TARGET_HOME/.local/share/icons"
  replace_user_path_with_dir "$theme_dir" "$TARGET_HOME/.local/share/icons/$MCMOJAVE_CURSOR_THEME"

  record_change "Installed McMojave cursor theme to $TARGET_HOME/.local/share/icons/$MCMOJAVE_CURSOR_THEME."
}

install_nautilus_open_any_terminal() {
  [[ "$INSTALL_NAUTILUS_OPEN_ANY_TERMINAL" == "1" ]] || {
    log "Nautilus Open Any Terminal installation is disabled."
    return 0
  }

  if ! enable_copr_repo "$NAUTILUS_OPEN_ANY_TERMINAL_COPR" "Nautilus Open Any Terminal"; then
    warn "Could not enable Nautilus Open Any Terminal COPR."
    return 0
  fi

  if dnf_install_optional nautilus-open-any-terminal; then
    record_change "Installed Nautilus Open Any Terminal."
  else
    return 0
  fi
}

configure_nautilus_open_any_terminal() {
  [[ "$INSTALL_NAUTILUS_OPEN_ANY_TERMINAL" == "1" ]] || return 0

  if [[ "$(run_as_user gsettings writable com.github.stunkymonkey.nautilus-open-any-terminal terminal 2>/dev/null)" == "true" ]]; then
    run_as_user gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal "$NAUTILUS_TERMINAL" || warn "Could not configure Nautilus Open Any Terminal."
    record_change "Configured Nautilus Open Any Terminal to use $NAUTILUS_TERMINAL."
  else
    warn "Nautilus Open Any Terminal gsettings schema is not available; cannot set terminal to $NAUTILUS_TERMINAL."
  fi

  if have_command nautilus; then
    run_as_user nautilus -q >/dev/null 2>&1 || true
  fi
}

github_latest_asset_url() {
  local api_url="$1"
  local asset_regex="$2"

  curl -fsSL "$api_url" |
    awk -F'"' -v regex="$asset_regex" '$2 == "browser_download_url" && $4 ~ regex { print $4; exit }'
}

download_as_user() {
  local url="$1"
  local dest="$2"

  run_as_user mkdir -p "$(dirname "$dest")"
  run_as_user curl -fL "$url" -o "$dest"
}


install_polaris() {
  [[ "$INSTALL_POLARIS" == "1" ]] || {
    log "Polaris installation is disabled."
    return 0
  }

  local fedora_version
  local rpm_url
  local rpm_path
  fedora_version="$(rpm -E %fedora)"
  rpm_url="$POLARIS_BASE_URL/Polaris-fedora${fedora_version}-x86_64.rpm"
  rpm_path="$TARGET_HOME/.cache/fedora-niri-setup/downloads/$(basename "$rpm_url")"

  log "Downloading Polaris package for Fedora $fedora_version."
  if ! download_as_user "$rpm_url" "$rpm_path"; then
    warn "Could not download Polaris package from $rpm_url."
    return 0
  fi

  if ! dnf_install_optional "$rpm_path"; then
    warn "Could not install Polaris package."
    return 0
  fi

  if [[ "$SETUP_POLARIS_HOST" == "1" ]]; then
    if have_command polaris; then
      log "Running Polaris host setup."
      if run_sudo polaris --setup-host; then
        record_change "Installed Polaris and ran host setup."
      else
        warn "Polaris installed, but host setup failed."
        record_change "Installed Polaris."
      fi
    else
      warn "Polaris package installed, but polaris was not found in PATH."
      record_change "Installed Polaris package."
    fi
  else
    record_change "Installed Polaris package."
  fi

  configure_polaris_autostart
}

install_default_apps() {
  install_vscode
  install_steam
  install_mcmojave_cursors
  install_nautilus_open_any_terminal
  install_polaris
}

enable_noctalia_copr() {
  [[ "$ENABLE_NOCTALIA_COPR" == "1" ]] || {
    log "Noctalia COPR enablement is disabled."
    return 0
  }

  enable_copr_repo "$NOCTALIA_COPR" "Noctalia packages"
  run_sudo "$DNF_BIN" makecache -y
}

install_noctalia_packages() {
  enable_noctalia_copr

  log "Installing Noctalia v5 and Noctalia Greeter."
  dnf_install "$NOCTALIA_PACKAGE" "$NOCTALIA_GREETER_PACKAGE"

  have_command noctalia || die "Noctalia package installation finished, but 'noctalia' was not found in PATH."

  if [[ -z "$NOCTALIA_GREETER_SESSION_BIN" ]]; then
    NOCTALIA_GREETER_SESSION_BIN="$(command -v noctalia-greeter-session || true)"
  fi

  [[ -n "$NOCTALIA_GREETER_SESSION_BIN" && -x "$NOCTALIA_GREETER_SESSION_BIN" ]] || die "Noctalia Greeter was installed, but noctalia-greeter-session was not found or is not executable."

  record_change "Installed Noctalia v5 and Noctalia Greeter."
}

clone_or_update_config_repo() {
  if [[ "$CONFIG_SOURCE_DIR_WAS_SET" == "1" ]]; then
    log "CONFIG_SOURCE_DIR was set explicitly; skipping config repository clone."
    return 0
  fi

  clone_or_update_git_repo "$CONFIG_REPO_URL" "$CONFIG_REPO_DIR" "$CONFIG_REPO_BRANCH"
  CONFIG_SOURCE_DIR="$CONFIG_REPO_DIR"
  record_change "Cloned or updated config repository $CONFIG_REPO_URL branch $CONFIG_REPO_BRANCH."
}

verify_config_source() {
  [[ -d "$CONFIG_SOURCE_DIR" ]] || die "Config source directory does not exist: $CONFIG_SOURCE_DIR"

  local missing=()
  [[ -d "$CONFIG_SOURCE_DIR/alacritty" ]] || missing+=("alacritty/")
  [[ -d "$CONFIG_SOURCE_DIR/niri" ]] || missing+=("niri/")
  [[ -f "$CONFIG_SOURCE_DIR/noctalia/$NOCTALIA_CONFIG_FILE" ]] || missing+=("noctalia/$NOCTALIA_CONFIG_FILE")
  [[ -d "$CONFIG_SOURCE_DIR/wallpapers" ]] || missing+=("wallpapers/")

  if ((${#missing[@]})); then
    die "Config source $CONFIG_SOURCE_DIR is missing required content: ${missing[*]}"
  fi

  log "Verified config source contains alacritty/, niri/, noctalia/$NOCTALIA_CONFIG_FILE, and wallpapers/."
}

install_user_configs() {
  log "Installing repo configs and overwriting existing target config directories."
  replace_user_path_with_dir "$CONFIG_SOURCE_DIR/alacritty" "$TARGET_HOME/.config/alacritty"
  replace_user_path_with_dir "$CONFIG_SOURCE_DIR/niri" "$TARGET_HOME/.config/niri"
  replace_user_path_with_dir "$CONFIG_SOURCE_DIR/noctalia" "$TARGET_HOME/$NOCTALIA_CONFIG_RELATIVE_DIR"
}

localized_pictures_dir() {
  if [[ -n "$WALLPAPER_PARENT_DIR" ]]; then
    printf '%s\n' "$WALLPAPER_PARENT_DIR"
    return 0
  fi

  local xdg_pictures=""
  if have_command xdg-user-dir; then
    xdg_pictures="$(run_as_user xdg-user-dir PICTURES 2>/dev/null || true)"
  fi

  if [[ -n "$xdg_pictures" && "$xdg_pictures" != "$TARGET_HOME" ]]; then
    printf '%s\n' "$xdg_pictures"
    return 0
  fi

  local user_locale="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
  case "$user_locale" in
    sv_SE*|sv_*)
      printf '%s\n' "$TARGET_HOME/Bilder"
      ;;
    *)
      printf '%s\n' "$TARGET_HOME/Pictures"
      ;;
  esac
}

install_wallpapers() {
  local pictures_dir
  pictures_dir="$(localized_pictures_dir)"
  log "Installing repo wallpapers into $pictures_dir/$WALLPAPER_SUBDIR."
  run_as_user mkdir -p "$pictures_dir"
  replace_user_path_with_dir "$CONFIG_SOURCE_DIR/wallpapers" "$pictures_dir/$WALLPAPER_SUBDIR"
}

detect_connected_outputs() {
  local status_file
  local output

  for status_file in /sys/class/drm/card*-*/status; do
    [[ -r "$status_file" ]] || continue
    [[ "$(cat "$status_file")" == "connected" ]] || continue
    output="$(basename "$(dirname "$status_file")")"
    output="${output#card*-}"
    [[ -n "$output" ]] || continue
    printf '%s\n' "$output"
  done
}

noctalia_wallpaper_outputs() {
  local output
  local configured_outputs=()
  local detected_outputs=()
  local seen_outputs=()
  local seen

  if [[ -n "$NOCTALIA_WALLPAPER_MONITORS" ]]; then
    read -r -a configured_outputs <<<"$NOCTALIA_WALLPAPER_MONITORS"
  fi
  mapfile -t detected_outputs < <(detect_connected_outputs)

  for output in "${configured_outputs[@]}" "${detected_outputs[@]}"; do
    [[ -n "$output" ]] || continue
    for seen in "${seen_outputs[@]}"; do
      [[ "$seen" == "$output" ]] && continue 2
    done
    seen_outputs+=("$output")
    printf '%s\n' "$output"
  done
}

configure_noctalia_settings() {
  local wallpaper_dir
  local wallpaper_path
  local config_file="$TARGET_HOME/$NOCTALIA_CONFIG_RELATIVE_DIR/$NOCTALIA_CONFIG_FILE"
  local marker_begin="# BEGIN fedora-niri-setup generated wallpaper settings"
  local marker_end="# END fedora-niri-setup generated wallpaper settings"
  local tmp
  local output
  local found_output=0

  wallpaper_dir="$(localized_pictures_dir)/$WALLPAPER_SUBDIR"
  wallpaper_path="$wallpaper_dir/$NOCTALIA_WALLPAPER_FILE"

  run_as_user mkdir -p "$(dirname "$config_file")"
  [[ -f "$config_file" ]] || run_as_user touch "$config_file"
  backup_user_path "$config_file"

  tmp="$(mktemp)"
  awk -v marker_begin="$marker_begin" -v marker_end="$marker_end" '
    $0 == marker_begin {
      skipping = 1
      next
    }
    $0 == marker_end {
      skipping = 0
      next
    }
    !skipping { print }
  ' "$config_file" >"$tmp"

  [[ ! -s "$tmp" ]] || printf '\n' >>"$tmp"

  cat >>"$tmp" <<EOF
$marker_begin
[wallpaper]
directory = "$wallpaper_dir"

    [wallpaper.default]
    path = "$wallpaper_path"

    [wallpaper.last]
    path = "$wallpaper_path"
EOF

  while IFS= read -r output; do
    [[ -n "$output" ]] || continue
    found_output=1
    cat >>"$tmp" <<EOF

    [wallpaper.monitors."$output"]
    path = "$wallpaper_path"
EOF
  done < <(noctalia_wallpaper_outputs)

  printf '%s\n' "$marker_end" >>"$tmp"

  if [[ "$found_output" == "0" ]]; then
    warn "No configured or connected monitor names were found; Noctalia wallpaper config will use default and last only."
  fi

  chmod 0644 "$tmp"
  run_as_user install -m 0644 "$tmp" "$config_file"
  rm -f "$tmp"

  if have_command noctalia; then
    run_as_user noctalia config validate "$config_file" || warn "Noctalia config validation failed for $config_file."
  fi

  record_change "Configured Noctalia wallpaper settings in $config_file."
}

configure_user_environment() {
  write_user_file "$TARGET_HOME/.config/environment.d/10-fedora-niri-setup.conf" 0644 <<EOF
XDG_CURRENT_DESKTOP=niri
XDG_SESSION_DESKTOP=niri
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland;xcb
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
XKB_DEFAULT_LAYOUT=$XKB_LAYOUT
XCURSOR_THEME=$GTK_CURSOR_THEME
XCURSOR_SIZE=$XCURSOR_SIZE
EOF

  write_user_file "$TARGET_HOME/.icons/default/index.theme" 0644 <<EOF
[Icon Theme]
Inherits=$GTK_CURSOR_THEME
EOF

  if have_command xdg-user-dirs-update; then
    run_as_user xdg-user-dirs-update || warn "xdg-user-dirs-update failed for $TARGET_USER."
  fi

  record_change "Configured basic user environment, cursor defaults, and Wayland app settings."
}

upsert_gtk_settings_file() {
  local path="$1"
  local tmp
  run_as_user mkdir -p "$(dirname "$path")"
  backup_user_path "$path"
  tmp="$(mktemp)"

  if [[ -f "$path" ]]; then
    awk \
      -v gtk_theme="$GTK_THEME_NAME" \
      -v prefer_dark="$GTK_APPLICATION_PREFER_DARK" \
      -v cursor_theme="$GTK_CURSOR_THEME" '
      function emit_missing() {
        if (!seen_theme) print "gtk-theme-name=" gtk_theme
        if (!seen_dark) print "gtk-application-prefer-dark-theme=" prefer_dark
        if (!seen_cursor) print "gtk-cursor-theme-name=" cursor_theme
      }
      BEGIN { in_settings = 0; saw_settings = 0 }
      /^\[Settings\]$/ {
        in_settings = 1
        saw_settings = 1
        print
        next
      }
      /^\[/ {
        if (in_settings) {
          emit_missing()
          in_settings = 0
        }
        print
        next
      }
      in_settings && /^gtk-theme-name=/ {
        print "gtk-theme-name=" gtk_theme
        seen_theme = 1
        next
      }
      in_settings && /^gtk-application-prefer-dark-theme=/ {
        print "gtk-application-prefer-dark-theme=" prefer_dark
        seen_dark = 1
        next
      }
      in_settings && /^gtk-cursor-theme-name=/ {
        print "gtk-cursor-theme-name=" cursor_theme
        seen_cursor = 1
        next
      }
      { print }
      END {
        if (in_settings) {
          emit_missing()
        } else if (!saw_settings) {
          print ""
          print "[Settings]"
          print "gtk-theme-name=" gtk_theme
          print "gtk-application-prefer-dark-theme=" prefer_dark
          print "gtk-cursor-theme-name=" cursor_theme
        }
      }
    ' "$path" >"$tmp"
  else
    cat >"$tmp" <<EOF
[Settings]
gtk-theme-name=$GTK_THEME_NAME
gtk-application-prefer-dark-theme=$GTK_APPLICATION_PREFER_DARK
gtk-cursor-theme-name=$GTK_CURSOR_THEME
EOF
  fi

  chmod 0644 "$tmp"
  run_as_user install -m 0644 "$tmp" "$path"
  rm -f "$tmp"
}

configure_gtk_dark_mode() {
  upsert_gtk_settings_file "$TARGET_HOME/.config/gtk-3.0/settings.ini"
  upsert_gtk_settings_file "$TARGET_HOME/.config/gtk-4.0/settings.ini"

  if [[ "$(run_as_user gsettings writable org.gnome.desktop.interface color-scheme 2>/dev/null)" == "true" ]]; then
    run_as_user gsettings set org.gnome.desktop.interface color-scheme "$GTK_COLOR_SCHEME" || warn "Could not set GNOME color-scheme."
  fi

  if [[ "$(run_as_user gsettings writable org.gnome.desktop.interface gtk-theme 2>/dev/null)" == "true" ]]; then
    run_as_user gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" || warn "Could not set GNOME gtk-theme."
  fi

  if [[ "$(run_as_user gsettings writable org.gnome.desktop.interface cursor-theme 2>/dev/null)" == "true" ]]; then
    run_as_user gsettings set org.gnome.desktop.interface cursor-theme "$GTK_CURSOR_THEME" || warn "Could not set GNOME cursor-theme."
  fi

  record_change "Configured basic GTK dark-mode and cursor preferences."
}

ensure_greeter_user() {
  if id "$GREETD_USER" >/dev/null 2>&1; then
    log "User '$GREETD_USER' already exists."
    return 0
  fi

  log "Creating system user '$GREETD_USER' for greetd."
  run_sudo useradd \
    --system \
    --no-create-home \
    --home-dir /var/lib/greetd \
    --shell /usr/sbin/nologin \
    "$GREETD_USER"
  record_change "Created system user $GREETD_USER for greetd."
}

configure_noctalia_greeter() {
  [[ "$ENABLE_GREETD" == "1" ]] || {
    log "greetd configuration is disabled."
    return 0
  }

  package_installed greetd || die "greetd is not installed; cannot configure Noctalia Greeter."

  if [[ -z "$NOCTALIA_GREETER_SESSION_BIN" ]]; then
    NOCTALIA_GREETER_SESSION_BIN="$(command -v noctalia-greeter-session || true)"
  fi

  [[ -n "$NOCTALIA_GREETER_SESSION_BIN" && -x "$NOCTALIA_GREETER_SESSION_BIN" ]] || die "Cannot configure greetd because noctalia-greeter-session was not found."

  ensure_greeter_user

  if ! compgen -G "/usr/share/wayland-sessions/*niri*.desktop" >/dev/null; then
    warn "No Niri session file found in /usr/share/wayland-sessions. Noctalia Greeter may not list Niri."
  fi

  run_sudo install -d -m 0755 /etc/greetd /var/lib/greetd /var/lib/noctalia-greeter /var/log
  run_sudo touch /var/log/noctalia-greeter.log /var/lib/noctalia-greeter/greeter.log
  run_sudo chown -R "$GREETD_USER:$GREETD_USER" /var/lib/greetd /var/lib/noctalia-greeter
  run_sudo chown "$GREETD_USER:$GREETD_USER" /var/log/noctalia-greeter.log

  local escaped_command
  local escaped_user
  escaped_command="$(toml_escape "$NOCTALIA_GREETER_SESSION_BIN -- --session niri")"
  escaped_user="$(toml_escape "$GREETD_USER")"

  write_system_file /etc/greetd/config.toml 0644 <<EOF
[terminal]
vt = 1

[default_session]
command = "$escaped_command"
user = "$escaped_user"
EOF

  write_system_file /var/lib/noctalia-greeter/greeter.conf 0644 <<EOF
keyboard_layout="$XKB_LAYOUT"
default_session="niri"
EOF
  run_sudo chown "$GREETD_USER:$GREETD_USER" /var/lib/noctalia-greeter/greeter.conf

  if [[ "$DISABLE_CONFLICTING_DISPLAY_MANAGERS" == "1" ]]; then
    local service
    for service in gdm.service sddm.service lightdm.service lxdm.service ly.service emptty.service; do
      if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        if ask_yes_no "Display manager $service is enabled and may conflict with greetd. Disable it?" y; then
          run_sudo systemctl disable "$service"
          record_change "Disabled conflicting display manager $service."
        else
          warn "$service was left enabled at your request."
        fi
      fi
    done
  fi

  run_sudo systemctl daemon-reload
  run_sudo systemctl enable greetd.service
  run_sudo systemctl set-default graphical.target
  record_change "Configured greetd to launch Noctalia Greeter with Niri as the default session."
}

# ═══════════════════════════════════════════════════════════════════════════════
# rEFInd UEFI bootloader migration
# ═══════════════════════════════════════════════════════════════════════════════
#
# Package: refind — available in Fedora official repos since F32.
#   Provides: /usr/share/rEFInd/refind/{refind_x64.efi,icons/,drivers_x64/}
#             /usr/sbin/refind-install  (unused here; we manage files directly)
#
# Secure Boot note: the refind EFI binary from Fedora's package is NOT signed by
# the Fedora Secure Boot key.  If SB is enabled this script will still install
# rEFInd and write the NVRAM entry, but it will NOT remove GRUB automatically.
# You must either disable SB in firmware or enroll a MOK (see summary output).
# ═══════════════════════════════════════════════════════════════════════════════

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

  for candidate in /boot/efi /efi /boot; do
    if mountpoint -q "$candidate" 2>/dev/null; then
      fstype="$(findmnt -n -o FSTYPE "$candidate" 2>/dev/null || true)"
      if [[ "$fstype" == "vfat" ]]; then
        esp="$candidate"
        break
      fi
    fi
  done

  if [[ -z "$esp" ]]; then
    local target
    while IFS= read -r target; do
      if [[ -d "${target}/EFI" ]]; then
        esp="$target"
        break
      fi
    done < <(findmnt -n -o TARGET --types vfat 2>/dev/null || true)
  fi

  [[ -n "$esp" ]] || die "Cannot detect EFI System Partition. Ensure it is mounted (vfat) and re-run."
  _REFIND_ESP="$esp"

  dev="$(findmnt -n -o SOURCE "$esp" 2>/dev/null || true)"
  [[ -n "$dev" ]] || die "Cannot determine block device backing ESP at $esp."
  dev="$(realpath "$dev" 2>/dev/null || printf '%s' "$dev")"

  local pkname partnum
  pkname="$(lsblk -ndo PKNAME "$dev" 2>/dev/null | head -1 || true)"
  partnum="$(lsblk -ndo PARTN "$dev" 2>/dev/null | head -1 || true)"

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
    warn "Secure Boot is ENABLED."
    warn "The refind EFI binary from Fedora repos is NOT signed with the Fedora Secure Boot key."
    warn "After installation you must either:"
    warn "  a) Enroll the rEFInd MOK cert:  sudo mokutil --import /usr/share/rEFInd/refind/keys/refind.cer"
    warn "     then reboot and follow MokManager prompts; or"
    warn "  b) Disable Secure Boot in your UEFI firmware settings."
    warn "GRUB will NOT be removed automatically until Secure Boot is resolved."
  fi
}

refind_resolve_cmdline() {
  local cmdline=""

  if [[ -s /etc/kernel/cmdline ]]; then
    cmdline="$(tr -s '[:space:]' ' ' </etc/kernel/cmdline | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$cmdline" ]] && printf '%s\n' "$cmdline" && return 0
  fi

  local bls_dir
  for bls_dir in /boot/loader/entries /boot/efi/loader/entries /efi/loader/entries; do
    [[ -d "$bls_dir" ]] || continue
    local bls_file
    bls_file="$(find "$bls_dir" -maxdepth 1 -name '*.conf' ! -name '*rescue*' -print 2>/dev/null \
                | sort -rV | head -1 || true)"
    if [[ -n "$bls_file" ]]; then
      cmdline="$(awk '/^options[[:space:]]/ { sub(/^options[[:space:]]+/,""); print; exit }' "$bls_file" \
                 | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -n "$cmdline" ]] && printf '%s\n' "$cmdline" && return 0
    fi
  done

  cmdline="$(sed -E 's/(^|[[:space:]])BOOT_IMAGE=[^[:space:]]*/\1/g' /proc/cmdline \
             | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$cmdline" ]] || die "Could not resolve a non-empty kernel command line from any source."
  printf '%s\n' "$cmdline"
}

refind_install_package() {
  # Package name is 'rEFInd' (case-sensitive) in Fedora 44.
  log "Installing rEFInd package from Fedora repositories."
  dnf_install rEFInd || die "Failed to install rEFInd. Check repo access and try: dnf info rEFInd."

  local share_dir="/usr/share/rEFInd/refind"
  [[ -f "${share_dir}/${_REFIND_EFI_NAME}" ]] || \
    die "rEFInd EFI binary not found at ${share_dir}/${_REFIND_EFI_NAME} after install."
  log "rEFInd source: ${share_dir}."
}

refind_copy_to_esp() {
  local share_dir="/usr/share/rEFInd/refind"
  local esp_dir="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}"
  local efi_dest="${esp_dir}/${_REFIND_EFI_NAME}"

  backup_system_path "$esp_dir"
  run_sudo install -d -m 0755 "$esp_dir"

  # EFI binary
  local tmp_local
  tmp_local="$(mktemp)"
  cp -f "${share_dir}/${_REFIND_EFI_NAME}" "$tmp_local"
  run_sudo install -m 0644 "$tmp_local" "$efi_dest"
  rm -f "$tmp_local"
  log "Installed: $efi_dest."

  # Icons (cosmetic but expected by rEFInd)
  if [[ -d "${share_dir}/icons" ]]; then
    local tmp_icons; tmp_icons="$(mktemp -d)"
    cp -a "${share_dir}/icons/." "${tmp_icons}/"
    run_sudo rm -rf "${esp_dir}/icons"
    run_sudo mkdir -p "${esp_dir}/icons"
    run_sudo cp -a "${tmp_icons}/." "${esp_dir}/icons/"
    rm -rf "$tmp_icons"
    log "Installed rEFInd icons to ${esp_dir}/icons/."
  fi

  # Filesystem drivers — allow rEFInd to read ext4/XFS/Btrfs /boot directly
  local drivers_src="${share_dir}/drivers_${_REFIND_ARCH}"
  if [[ -d "$drivers_src" ]]; then
    local tmp_drv; tmp_drv="$(mktemp -d)"
    cp -a "${drivers_src}/." "${tmp_drv}/"
    run_sudo rm -rf "${esp_dir}/drivers_${_REFIND_ARCH}"
    run_sudo mkdir -p "${esp_dir}/drivers_${_REFIND_ARCH}"
    run_sudo cp -a "${tmp_drv}/." "${esp_dir}/drivers_${_REFIND_ARCH}/"
    rm -rf "$tmp_drv"
    log "Installed rEFInd filesystem drivers (${_REFIND_ARCH})."
  else
    warn "No drivers at ${drivers_src}; rEFInd may not read /boot on non-ESP filesystems."
  fi

  # Secure Boot: chain shim → rEFInd (shim looks for grubx64.efi in its own dir)
  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
    local shim_src="" shim_candidate
    for shim_candidate in \
        "${_REFIND_ESP}/EFI/fedora/shimx64.efi" \
        "${_REFIND_ESP}/EFI/fedora/shim.efi" \
        "/usr/share/shim-signed/shimx64.efi"; do
      [[ -f "$shim_candidate" ]] && shim_src="$shim_candidate" && break
    done
    if [[ -n "$shim_src" ]]; then
      run_sudo cp -f "$shim_src" "${esp_dir}/shim${_REFIND_ARCH}.efi"
      # shim's compiled-in second-stage filename is grubx64.efi — alias rEFInd to that name
      run_sudo cp -f "$efi_dest" "${esp_dir}/grub${_REFIND_ARCH}.efi"
      log "SB: copied shim and created grub${_REFIND_ARCH}.efi alias → NVRAM will target shimx64.efi."
    else
      warn "Secure Boot is enabled but shimx64.efi was not found on the ESP."
      warn "NVRAM will target refind_x64.efi directly; firmware must trust it or boot will fail."
    fi
  fi
}

refind_write_conf() {
  local esp_dir="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}"
  local conf_dest="${esp_dir}/refind.conf"

  backup_system_path "$conf_dest"

  local tmp; tmp="$(mktemp)"
  cat >"$tmp" <<EOF
# rEFInd configuration — written by fedora-niri-setup.sh on ${TIMESTAMP}
# Delete this file and re-run the script to regenerate it.

timeout ${REFIND_TIMEOUT}

# Auto-detect all Linux kernels on all readable volumes.
scan_all_linux_kernels true

# Show each kernel as a separate entry (not folded by version).
fold_linux_kernels false

# Recognise kernels stored under these extra name patterns.
extra_kernel_version_strings linux,linux-lts,linux-hardened,linux-zen

# Skip volumes labelled as recovery/diagnostic environments.
dont_scan_volumes "Recovery,RECOVERY,WRE"

# Hide rescue kernels from the boot menu.
dont_scan_files rescue,fallback

# Boot options come from /boot/refind_linux.conf next to each kernel.
# Do not manage NVRAM from inside rEFInd (we did it with efibootmgr).
use_nvram false

# Default to the most recently booted entry.
default_selection lastbooted

# Let the firmware choose the graphics resolution.
resolution auto
EOF
  run_sudo install -m 0644 "$tmp" "$conf_dest"
  rm -f "$tmp"
  log "Wrote rEFInd config: $conf_dest."
}

refind_write_linux_conf() {
  local cmdline
  cmdline="$(refind_resolve_cmdline)"
  local cmdline_verbose
  cmdline_verbose="$(printf '%s' "$cmdline" | sed 's/ quiet\b//g; s/ splash\b//g; s/ rhgb\b//g' | tr -s ' ')"

  local conf_dest="/boot/refind_linux.conf"
  backup_system_path "$conf_dest"

  local tmp; tmp="$(mktemp)"
  cat >"$tmp" <<EOF
# /boot/refind_linux.conf — per-kernel rEFInd boot options
# Written by fedora-niri-setup.sh on ${TIMESTAMP}.
# Edit this file to customise kernel parameters.
# Format:  "Menu label"  "kernel options"

"Boot normally"            "${cmdline}"
"Boot verbose"             "${cmdline_verbose} systemd.show_status=1"
"Boot to single-user"      "${cmdline} single"
"Boot to emergency shell"  "${cmdline} systemd.unit=emergency.target"
EOF
  run_sudo install -m 0644 "$tmp" "$conf_dest"
  rm -f "$tmp"
  log "Wrote /boot/refind_linux.conf."
  log "Kernel cmdline: ${cmdline}."
}

refind_register_nvram() {
  have_command efibootmgr || die "efibootmgr is required to register the rEFInd NVRAM entry."

  # For Secure Boot we chain through shim; otherwise load rEFInd directly.
  local loader_rel
  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]] && \
     run_sudo test -f "${_REFIND_ESP}/${REFIND_ESP_SUBDIR}/shim${_REFIND_ARCH}.efi"; then
    loader_rel="${REFIND_ESP_SUBDIR}/shim${_REFIND_ARCH}.efi"
  else
    loader_rel="${REFIND_ESP_SUBDIR}/${_REFIND_EFI_NAME}"
  fi
  # UEFI uses backslash-separated paths
  local loader_uefi
  loader_uefi="\\$(printf '%s' "$loader_rel" | tr '/' '\\')"

  # Remove any existing rEFInd NVRAM entries (idempotency)
  local boot_entry boot_num
  while IFS= read -r boot_entry; do
    [[ "$boot_entry" =~ ^Boot([0-9A-Fa-f]{4}) ]] || continue
    boot_num="${BASH_REMATCH[1]}"
    if echo "$boot_entry" | grep -qi "refind\|${REFIND_ENTRY_LABEL}"; then
      log "Removing stale rEFInd NVRAM entry: Boot${boot_num}."
      run_sudo efibootmgr --bootnum "$boot_num" --delete-bootnum 2>/dev/null || \
        warn "Could not remove Boot${boot_num}."
    fi
  done < <(run_sudo efibootmgr -v 2>/dev/null || true)

  log "Creating NVRAM entry '${REFIND_ENTRY_LABEL}' → ${loader_uefi}."
  run_sudo efibootmgr \
    --create \
    --disk   "$_REFIND_ESP_DISK" \
    --part   "$_REFIND_ESP_PARTNUM" \
    --label  "$REFIND_ENTRY_LABEL" \
    --loader "$loader_uefi" \
    --unicode || die "efibootmgr failed to create the rEFInd NVRAM entry."

  # Identify the newly created entry number
  _REFIND_BOOT_NUM=""
  while IFS= read -r boot_entry; do
    if echo "$boot_entry" | grep -qF "$REFIND_ENTRY_LABEL"; then
      [[ "$boot_entry" =~ ^Boot([0-9A-Fa-f]{4}) ]] && \
        _REFIND_BOOT_NUM="${BASH_REMATCH[1]}" && break
    fi
  done < <(run_sudo efibootmgr 2>/dev/null || true)
  [[ -n "$_REFIND_BOOT_NUM" ]] || die "rEFInd NVRAM entry not found after creation."

  # Place rEFInd first in BootOrder
  local cur_order new_order filtered
  cur_order="$(run_sudo efibootmgr 2>/dev/null | awk '/^BootOrder:/{print $2}' || true)"
  if [[ -n "$cur_order" ]]; then
    filtered="$(printf '%s' "$cur_order" | tr ',' '\n' \
                | grep -iv "^${_REFIND_BOOT_NUM}$" | tr '\n' ',' | sed 's/,$//')"
    new_order="${_REFIND_BOOT_NUM}${filtered:+,${filtered}}"
  else
    new_order="$_REFIND_BOOT_NUM"
  fi
  run_sudo efibootmgr --bootorder "$new_order" || \
    warn "Could not set BootOrder. Set manually: sudo efibootmgr --bootorder ${new_order}"

  log "rEFInd is Boot${_REFIND_BOOT_NUM}, first in BootOrder (${new_order})."
  record_change "Registered rEFInd as Boot${_REFIND_BOOT_NUM} and placed it first in BootOrder."
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

  if [[ -f /boot/refind_linux.conf ]]; then
    log "  [✓] /boot/refind_linux.conf present"
  else
    warn "  [✗] /boot/refind_linux.conf missing"
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

  local kcount=0
  kcount="$(find /boot -maxdepth 1 -name 'vmlinuz-*' ! -name '*rescue*' -print 2>/dev/null | wc -l || echo 0)"
  kcount="${kcount//[[:space:]]/}"
  if (( kcount > 0 )); then
    log "  [✓] Found ${kcount} bootable kernel(s) in /boot"
  else
    warn "  [✗] No non-rescue kernels found in /boot"
    errors=$(( errors + 1 ))
  fi

  (( errors == 0 )) || die "rEFInd validation failed ($errors error(s)). Fix the warnings above before removing GRUB."
  log "rEFInd validation passed."
}

refind_backup_grub() {
  local bdir="${REFIND_RECOVERY_DIR}/${TIMESTAMP}"
  run_sudo install -d -m 0750 "$bdir"

  local efi_fedora="${_REFIND_ESP}/EFI/fedora"
  if [[ -d "$efi_fedora" ]]; then
    run_sudo cp -a "$efi_fedora" "${bdir}/EFI-fedora"
    log "Backed up $efi_fedora → ${bdir}/EFI-fedora."
  fi

  local f
  for f in /etc/default/grub /boot/grub2/grub.cfg; do
    [[ -f "$f" ]] && run_sudo cp -a "$f" "${bdir}/" && log "Backed up $f."
  done

  run_sudo efibootmgr -v 2>/dev/null >"${bdir}/efibootmgr-pre-removal.txt" || true
  log "Saved efibootmgr state → ${bdir}/efibootmgr-pre-removal.txt."
  printf '%s\n' "$bdir"
}

refind_remove_grub() {
  local bdir="$1"

  # Remove Fedora GRUB NVRAM entries — only those whose loader path contains
  # EFI\fedora (verbose efibootmgr output includes the loader path).
  log "Removing Fedora GRUB NVRAM entries."
  local boot_entry boot_num
  while IFS= read -r boot_entry; do
    [[ "$boot_entry" =~ ^Boot([0-9A-Fa-f]{4}) ]] || continue
    boot_num="${BASH_REMATCH[1]}"
    [[ "${boot_num^^}" == "${_REFIND_BOOT_NUM^^}" ]] && continue
    if echo "$boot_entry" | grep -qiE '\\EFI\\fedora\\|File.*fedora'; then
      log "  Removing GRUB NVRAM entry Boot${boot_num}."
      run_sudo efibootmgr --bootnum "$boot_num" --delete-bootnum 2>/dev/null || \
        warn "  Could not remove Boot${boot_num}."
      record_change "Removed GRUB NVRAM entry Boot${boot_num}."
    fi
  done < <(run_sudo efibootmgr -v 2>/dev/null || true)

  # Remove GRUB EFI packages — keep grubby (used by kernel-install hooks) and
  # grub2-tools-minimal (provides grub2-editenv used by some scripts).
  # ⚠ Verify package names against: dnf list installed 'grub2*'
  local grub_pkgs=(
    grub2-efi-x64
    grub2-efi-x64-cdboot
    grub2-efi-aa64
    grub2-efi-ia32
    grub2-efi-x64-modules
    grub2-common
    grub2-tools-extra
  )
  local to_remove=() pkg
  for pkg in "${grub_pkgs[@]}"; do
    package_installed "$pkg" && to_remove+=("$pkg")
  done
  if (( ${#to_remove[@]} > 0 )); then
    log "Removing GRUB packages: ${to_remove[*]}."
    run_sudo "$DNF_BIN" remove -y "${to_remove[@]}" || \
      warn "Some GRUB packages could not be removed: ${to_remove[*]}."
    record_change "Removed GRUB packages: ${to_remove[*]}."
  else
    log "No target GRUB packages were installed."
  fi

  # Remove GRUB EFI files from the ESP.  Keep shimx64.efi and MokManager.efi —
  # shim is needed for Secure Boot and for signing other EFI tools.
  local efi_fedora="${_REFIND_ESP}/EFI/fedora"
  if [[ -d "$efi_fedora" ]]; then
    local grub_files=(
      grubx64.efi grubaa64.efi grubenv grub.cfg
      fonts locale
    )
    local gf
    for gf in "${grub_files[@]}"; do
      local fp="${efi_fedora}/${gf}"
      if run_sudo test -e "$fp"; then
        run_sudo rm -rf "$fp"
        log "  Removed: $fp."
        record_change "Removed GRUB EFI file: $fp."
      fi
    done
    # Remove the directory only if empty (shim/MOK files may remain)
    if [[ -z "$(run_sudo find "$efi_fedora" -maxdepth 1 -mindepth 1 -print 2>/dev/null | head -1)" ]]; then
      run_sudo rmdir "$efi_fedora" 2>/dev/null || true
      log "  Removed empty directory: $efi_fedora."
    else
      log "  Kept $efi_fedora (non-GRUB files remain, e.g. shim/MokManager)."
    fi
  fi

  log "GRUB removal complete. Recovery backup: $bdir."
}

refind_print_summary() {
  local bdir="${1:-n/a}"

  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_CYAN" "$COLOR_RESET"
  printf '%s  rEFInd Bootloader Summary%s\n' "$COLOR_CYAN" "$COLOR_RESET"
  printf '%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_CYAN" "$COLOR_RESET"
  printf '\n'
  printf '  EFI System Partition : %s\n'            "$_REFIND_ESP"
  printf '  rEFInd EFI binary    : %s/%s/%s\n'     "$_REFIND_ESP" "$REFIND_ESP_SUBDIR" "$_REFIND_EFI_NAME"
  printf '  rEFInd config        : %s/%s/refind.conf\n' "$_REFIND_ESP" "$REFIND_ESP_SUBDIR"
  printf '  Kernel options file  : /boot/refind_linux.conf\n'
  printf '  Secure Boot state    : %s\n'            "$_REFIND_SECURE_BOOT"
  printf '  NVRAM entry          : Boot%s  (%s)\n' "${_REFIND_BOOT_NUM:-???}" "$REFIND_ENTRY_LABEL"
  printf '  GRUB backup dir      : %s\n'            "$bdir"
  printf '\n'
  printf '  %sCurrent UEFI boot order:%s\n' "$COLOR_BOLD" "$COLOR_RESET"
  run_sudo efibootmgr 2>/dev/null | grep -E '^Boot[0-9A-Fa-f]{4}' | sed 's/^/    /' || true
  printf '\n'
  printf '  %sRecovery (if rEFInd does not boot):%s\n' "$COLOR_YELLOW" "$COLOR_RESET"
  printf '  1. Boot Fedora live media.\n'
  printf '  2. Mount the ESP and restore GRUB EFI files:\n'
  printf '       sudo mount %s /mnt\n' "$_REFIND_ESP_DISK"
  printf '       sudo cp -a %s/EFI-fedora /mnt/EFI/fedora\n' "$bdir"
  printf '  3. Re-register the GRUB NVRAM entry:\n'
  printf '       sudo efibootmgr --create --disk %s --part %s \\\n' \
    "$_REFIND_ESP_DISK" "$_REFIND_ESP_PARTNUM"
  printf '         --label "fedora" --loader "\\\\EFI\\\\fedora\\\\shimx64.efi"\n'
  printf '  4. Reboot.\n'
  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
    printf '\n  %sSecure Boot — action required before rEFInd will start:%s\n' "$COLOR_YELLOW" "$COLOR_RESET"
    printf '  Option A — Enroll MOK certificate:\n'
    printf '    sudo mokutil --import /usr/share/rEFInd/refind/keys/refind.cer\n'
    printf '    Reboot and follow the blue MokManager screen.\n'
    printf '  Option B — Disable Secure Boot in UEFI firmware settings.\n'
  fi
  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n' "$COLOR_CYAN" "$COLOR_RESET"
}

install_refind() {
  [[ "$INSTALL_REFIND" == "1" ]] || {
    log "rEFInd installation is disabled (INSTALL_REFIND=0)."
    return 0
  }

  warn "REPLACING BOOTLOADER: rEFInd will become the primary UEFI boot manager."
  warn "Have a Fedora live USB ready in case of boot failure."
  if [[ "$ASSUME_YES" != "1" ]]; then
    ask_yes_no "Continue with rEFInd bootloader migration?" y || {
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
  refind_copy_to_esp
  refind_write_conf
  refind_write_linux_conf
  refind_register_nvram
  refind_validate

  local bdir="n/a (GRUB not removed)"
  if [[ "$REFIND_REMOVE_GRUB" == "1" ]]; then
    if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
      warn "Secure Boot is enabled — GRUB will NOT be removed automatically."
      warn "Resolve Secure Boot (see summary below), verify rEFInd boots, then re-run"
      warn "with REFIND_REMOVE_GRUB=1 and INSTALL_REFIND=0 to skip reinstall."
    else
      bdir="$(refind_backup_grub)"
      refind_remove_grub "$bdir"
      log "Post-removal validation."
      refind_validate
    fi
  else
    log "GRUB not removed (REFIND_REMOVE_GRUB=0). Verify boot, then re-run with REFIND_REMOVE_GRUB=1."
  fi

  refind_print_summary "$bdir"
  record_change "Installed rEFInd UEFI bootloader."
}

print_summary() {
  local item

  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  Setup complete%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '\n'
  printf '  Log:            %s\n' "$LOG_FILE"
  printf '  User backups:   %s\n' "$USER_BACKUP_ROOT"
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
  print_banner
  section "Fedora Niri setup"
  require_fedora
  resolve_target_user
  prepare_runtime

  section "Base packages"
  install_fedora_packages

  section "Default apps"
  install_default_apps

  section "Boot visuals"
  configure_plymouth_and_grub

  section "Noctalia"
  install_noctalia_packages

  section "Repo configs"
  clone_or_update_config_repo
  verify_config_source
  install_user_configs

  section "User settings"
  configure_user_environment
  install_wallpapers
  configure_noctalia_settings
  configure_gtk_dark_mode
  configure_nautilus_open_any_terminal

  section "Greeter"
  configure_noctalia_greeter

  section "Bootloader (rEFInd)"
  install_refind

  section "Summary"
  print_summary
}

main "$@"
