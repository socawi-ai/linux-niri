#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_REPO_URL="${CONFIG_REPO_URL:-https://github.com/socawi-ai/linux-niri}"
CONFIG_REPO_DIR_WAS_SET=0
CONFIG_SOURCE_DIR_WAS_SET=0
USER_BACKUP_ROOT_WAS_SET=0
MCMOJAVE_CURSORS_DIR_WAS_SET=0
[[ -n "${CONFIG_REPO_DIR+x}" ]] && CONFIG_REPO_DIR_WAS_SET=1
[[ -n "${CONFIG_SOURCE_DIR+x}" ]] && CONFIG_SOURCE_DIR_WAS_SET=1
[[ -n "${USER_BACKUP_ROOT+x}" ]] && USER_BACKUP_ROOT_WAS_SET=1
[[ -n "${MCMOJAVE_CURSORS_DIR+x}" ]] && MCMOJAVE_CURSORS_DIR_WAS_SET=1
CONFIG_REPO_BRANCH="${CONFIG_REPO_BRANCH:-main}"
CONFIG_REPO_DIR="${CONFIG_REPO_DIR:-$HOME/.cache/fedora-niri-setup/linux-niri}"
CONFIG_SOURCE_DIR="${CONFIG_SOURCE_DIR:-}"
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
ASSUME_YES="${ASSUME_YES:-1}"
EXTRA_FEDORA_PACKAGES="${EXTRA_FEDORA_PACKAGES:-}"
DNF_SKIP_UNAVAILABLE="${DNF_SKIP_UNAVAILABLE:-1}"

ENABLE_NOCTALIA_COPR="${ENABLE_NOCTALIA_COPR:-1}"
ENABLE_GREETD="${ENABLE_GREETD:-1}"
ENABLE_FEDORA_THIRD_PARTY_REPOS="${ENABLE_FEDORA_THIRD_PARTY_REPOS:-1}"
ENABLE_RPMFUSION="${ENABLE_RPMFUSION:-1}"
INSTALL_FLATPAK="${INSTALL_FLATPAK:-1}"
ADD_FLATHUB_REMOTE="${ADD_FLATHUB_REMOTE:-1}"
FLATHUB_REMOTE_URL="${FLATHUB_REMOTE_URL:-https://dl.flathub.org/repo/flathub.flatpakrepo}"
INSTALL_PROTON_MAIL="${INSTALL_PROTON_MAIL:-1}"
PROTON_MAIL_FLATPAK_ID="${PROTON_MAIL_FLATPAK_ID:-me.proton.Mail}"
INSTALL_LOCALSEND="${INSTALL_LOCALSEND:-1}"
LOCALSEND_FLATPAK_ID="${LOCALSEND_FLATPAK_ID:-org.localsend.localsend_app}"
INSTALL_PROTONUP_QT="${INSTALL_PROTONUP_QT:-1}"
PROTONUP_QT_FLATPAK_ID="${PROTONUP_QT_FLATPAK_ID:-net.davidotek.pupgui2}"
INSTALL_STEAM="${INSTALL_STEAM:-1}"
# Micro-compositor Valve ships on the Steam Deck; lets Proton games run at a
# fixed resolution/scale and get their own fullscreen surface instead of
# fighting niri's own window management. Launch a game via Steam's per-game
# launch options with: gamescope -- %command%
INSTALL_GAMESCOPE="${INSTALL_GAMESCOPE:-1}"
INSTALL_VSCODE="${INSTALL_VSCODE:-1}"
INSTALL_MCMOJAVE_CURSORS="${INSTALL_MCMOJAVE_CURSORS:-1}"
INSTALL_NAUTILUS_OPEN_ANY_TERMINAL="${INSTALL_NAUTILUS_OPEN_ANY_TERMINAL:-1}"
INSTALL_LACT="${INSTALL_LACT:-1}"
ENABLE_LACT_SERVICE="${ENABLE_LACT_SERVICE:-1}"
CONFIGURE_PLYMOUTH="${CONFIGURE_PLYMOUTH:-1}"
DISABLE_CONFLICTING_DISPLAY_MANAGERS="${DISABLE_CONFLICTING_DISPLAY_MANAGERS:-1}"
NOCTALIA_COPR="${NOCTALIA_COPR:-lionheartp/Hyprland}"
NOCTALIA_PACKAGE="${NOCTALIA_PACKAGE:-noctalia-git}"
NOCTALIA_GREETER_PACKAGE="${NOCTALIA_GREETER_PACKAGE:-noctalia-greeter}"
NAUTILUS_OPEN_ANY_TERMINAL_COPR="${NAUTILUS_OPEN_ANY_TERMINAL_COPR:-monkeygold/nautilus-open-any-terminal}"
NAUTILUS_TERMINAL="${NAUTILUS_TERMINAL:-alacritty}"
LACT_COPR="${LACT_COPR:-ilyaz/LACT}"
LACT_PACKAGE="${LACT_PACKAGE:-lact}"
MCMOJAVE_CURSORS_REPO="${MCMOJAVE_CURSORS_REPO:-https://github.com/vinceliuice/McMojave-cursors}"
MCMOJAVE_CURSORS_DIR="${MCMOJAVE_CURSORS_DIR:-$HOME/.cache/fedora-niri-setup/McMojave-cursors}"
MCMOJAVE_CURSOR_THEME="${MCMOJAVE_CURSOR_THEME:-McMojave-cursors}"
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

XKB_LAYOUT="${XKB_LAYOUT:-se}"
GTK_COLOR_SCHEME="${GTK_COLOR_SCHEME:-prefer-dark}"
GTK_THEME_NAME="${GTK_THEME_NAME:-Adwaita-dark}"
GTK_APPLICATION_PREFER_DARK="${GTK_APPLICATION_PREFER_DARK:-1}"
GTK_CURSOR_THEME="${GTK_CURSOR_THEME:-$MCMOJAVE_CURSOR_THEME}"
XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
WALLPAPER_PARENT_DIR="${WALLPAPER_PARENT_DIR:-}"
WALLPAPER_SUBDIR="${WALLPAPER_SUBDIR:-wallpapers}"
# The repo now ships wallpapers as a single archive (smaller Git history than
# committing every image loose) rather than as loose files in wallpapers/.
WALLPAPER_ARCHIVE_NAME="${WALLPAPER_ARCHIVE_NAME:-wallpapers.tar.xz}"

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

TOTAL_SECTIONS=9

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

extract_archive_into_user_dir() {
  # Like replace_user_path_with_dir, but extracts a tar archive into $dest
  # instead of copying a directory.
  local archive="$1"
  local dest="$2"
  [[ -f "$archive" ]] || die "Expected archive file $archive."

  case "$dest" in
    "$TARGET_HOME"/*) ;;
    *) die "Refusing to extract into path outside target home: $dest" ;;
  esac

  backup_user_path "$dest"
  run_as_user rm -rf -- "$dest"
  run_as_user mkdir -p "$dest"
  run_as_user tar -xf "$archive" -C "$dest"
  record_change "Extracted $(basename "$archive") into $dest."
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
    git-lfs
    gh
    tar
    xz
    fedora-workstation-repositories
    grubby
    grub2-tools
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

install_flatpak() {
  [[ "$INSTALL_FLATPAK" == "1" ]] || {
    log "Flatpak installation is disabled."
    return 0
  }

  log "Installing Flatpak."
  if ! dnf_install_optional flatpak; then
    return 0
  fi
  record_change "Installed Flatpak."

  [[ "$ADD_FLATHUB_REMOTE" == "1" ]] || {
    log "Flathub remote setup is disabled."
    return 0
  }

  # System-wide (not --user), matching dnf's system-wide package scope used
  # everywhere else in this script — makes Flathub apps available to any
  # user on the machine, not just TARGET_USER.
  if run_sudo flatpak remote-add --if-not-exists flathub "$FLATHUB_REMOTE_URL"; then
    record_change "Added the Flathub remote ($FLATHUB_REMOTE_URL)."
  else
    warn "Could not add the Flathub remote."
  fi
}

install_proton_mail() {
  [[ "$INSTALL_PROTON_MAIL" == "1" ]] || {
    log "Proton Mail installation is disabled."
    return 0
  }

  if ! have_command flatpak; then
    warn "Flatpak is not installed; cannot install Proton Mail ($PROTON_MAIL_FLATPAK_ID)."
    return 0
  fi

  log "Installing Proton Mail ($PROTON_MAIL_FLATPAK_ID) from Flathub."
  local args=(install flathub "$PROTON_MAIL_FLATPAK_ID")
  [[ "$ASSUME_YES" == "1" ]] && args+=(-y)

  if run_sudo flatpak "${args[@]}"; then
    record_change "Installed Proton Mail ($PROTON_MAIL_FLATPAK_ID) from Flathub."
  else
    warn "Could not install Proton Mail from Flathub."
  fi
}

install_localsend() {
  [[ "$INSTALL_LOCALSEND" == "1" ]] || {
    log "LocalSend installation is disabled."
    return 0
  }

  if ! have_command flatpak; then
    warn "Flatpak is not installed; cannot install LocalSend ($LOCALSEND_FLATPAK_ID)."
    return 0
  fi

  log "Installing LocalSend ($LOCALSEND_FLATPAK_ID) from Flathub."
  local args=(install flathub "$LOCALSEND_FLATPAK_ID")
  [[ "$ASSUME_YES" == "1" ]] && args+=(-y)

  if run_sudo flatpak "${args[@]}"; then
    record_change "Installed LocalSend ($LOCALSEND_FLATPAK_ID) from Flathub."
  else
    warn "Could not install LocalSend from Flathub."
  fi
}

install_protonup_qt() {
  [[ "$INSTALL_PROTONUP_QT" == "1" ]] || {
    log "ProtonUp-Qt installation is disabled."
    return 0
  }

  if ! have_command flatpak; then
    warn "Flatpak is not installed; cannot install ProtonUp-Qt ($PROTONUP_QT_FLATPAK_ID)."
    return 0
  fi

  log "Installing ProtonUp-Qt ($PROTONUP_QT_FLATPAK_ID) from Flathub."
  local args=(install flathub "$PROTONUP_QT_FLATPAK_ID")
  [[ "$ASSUME_YES" == "1" ]] && args+=(-y)

  if run_sudo flatpak "${args[@]}"; then
    record_change "Installed ProtonUp-Qt ($PROTONUP_QT_FLATPAK_ID) from Flathub."
  else
    warn "Could not install ProtonUp-Qt from Flathub."
  fi
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

  install_gamescope
}

install_gamescope() {
  [[ "$INSTALL_GAMESCOPE" == "1" ]] || {
    log "gamescope installation is disabled."
    return 0
  }

  log "Installing gamescope."
  if dnf_install_optional gamescope; then
    record_change "Installed gamescope."
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
  if have_command grub2-mkconfig; then
    run_sudo grub2-mkconfig -o "$GRUB_MKCONFIG_OUTPUT"
    record_change "Regenerated GRUB config at $GRUB_MKCONFIG_OUTPUT."
  else
    warn "grub2-mkconfig was not found; GRUB config was not regenerated."
  fi
}

configure_plymouth_and_grub() {
  [[ "$CONFIGURE_PLYMOUTH" == "1" ]] || return 0

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

  upsert_grub_default GRUB_TIMEOUT "\"$GRUB_TIMEOUT_SECONDS\""
  upsert_grub_default GRUB_TIMEOUT_STYLE "\"menu\""
  upsert_grub_default GRUB_GFXMODE "\"$GRUB_GFXMODE\""
  upsert_grub_default GRUB_TERMINAL_OUTPUT "\"gfxterm\""

  regenerate_grub_config
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

  # Registers git-lfs's smudge/clean filters for $TARGET_USER so any
  # LFS-tracked files (e.g. this repo's wallpapers/) are actually downloaded
  # on clone/checkout instead of left as pointer stubs. Idempotent, and a
  # harmless no-op for repos that don't use LFS at all.
  have_command git-lfs && run_as_user git lfs install

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

  # Belt-and-suspenders: the smudge filter registered above should already
  # materialize LFS content during the clone/checkout/reset above, but an
  # explicit pull removes any doubt. No-op for repos with no LFS tracking.
  have_command git-lfs && run_as_user git -C "$repo_dir" lfs pull
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

install_lact() {
  [[ "$INSTALL_LACT" == "1" ]] || {
    log "LACT installation is disabled."
    return 0
  }

  if ! enable_copr_repo "$LACT_COPR" "LACT"; then
    warn "Could not enable LACT COPR."
    return 0
  fi

  if ! dnf_install_optional "$LACT_PACKAGE"; then
    return 0
  fi
  record_change "Installed LACT ($LACT_PACKAGE) for AMD/Nvidia/Intel GPU control."

  [[ "$ENABLE_LACT_SERVICE" == "1" ]] || {
    log "LACT service (lactd) autostart is disabled."
    return 0
  }

  if run_sudo systemctl enable --now lactd.service; then
    record_change "Enabled and started the lactd service."
  else
    warn "Could not enable and start lactd.service."
  fi
}

install_default_apps() {
  install_vscode
  install_steam
  install_mcmojave_cursors
  install_nautilus_open_any_terminal
  install_lact
  install_proton_mail
  install_localsend
  install_protonup_qt
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
  local pictures_dir wallpaper_dest archive
  pictures_dir="$(localized_pictures_dir)"
  wallpaper_dest="$pictures_dir/$WALLPAPER_SUBDIR"
  archive="$CONFIG_SOURCE_DIR/wallpapers/$WALLPAPER_ARCHIVE_NAME"

  run_as_user mkdir -p "$pictures_dir"

  if [[ -f "$archive" ]]; then
    log "Extracting repo wallpapers ($WALLPAPER_ARCHIVE_NAME) into $wallpaper_dest."
    extract_archive_into_user_dir "$archive" "$wallpaper_dest"
  else
    log "Installing repo wallpapers into $wallpaper_dest."
    replace_user_path_with_dir "$CONFIG_SOURCE_DIR/wallpapers" "$wallpaper_dest"
  fi
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
  install_flatpak

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

  section "Summary"
  print_summary
}

main "$@"
