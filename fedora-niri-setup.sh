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
ASSUME_YES="${ASSUME_YES:-0}"
EXTRA_FEDORA_PACKAGES="${EXTRA_FEDORA_PACKAGES:-}"

ENABLE_NOCTALIA_COPR="${ENABLE_NOCTALIA_COPR:-1}"
ENABLE_GREETD="${ENABLE_GREETD:-1}"
ENABLE_FLATHUB="${ENABLE_FLATHUB:-1}"
INSTALL_STEAM="${INSTALL_STEAM:-1}"
INSTALL_BITWARDEN="${INSTALL_BITWARDEN:-1}"
INSTALL_VSCODE="${INSTALL_VSCODE:-1}"
INSTALL_MCMOJAVE_CURSORS="${INSTALL_MCMOJAVE_CURSORS:-1}"
INSTALL_NAUTILUS_OPEN_ANY_TERMINAL="${INSTALL_NAUTILUS_OPEN_ANY_TERMINAL:-1}"
INSTALL_LSFG_VK="${INSTALL_LSFG_VK:-1}"
INSTALL_POLARIS="${INSTALL_POLARIS:-1}"
SETUP_POLARIS_HOST="${SETUP_POLARIS_HOST:-1}"
DISABLE_CONFLICTING_DISPLAY_MANAGERS="${DISABLE_CONFLICTING_DISPLAY_MANAGERS:-1}"
NOCTALIA_COPR="${NOCTALIA_COPR:-lionheartp/Hyprland}"
NOCTALIA_PACKAGE="${NOCTALIA_PACKAGE:-noctalia-git}"
NOCTALIA_GREETER_PACKAGE="${NOCTALIA_GREETER_PACKAGE:-noctalia-greeter}"
NAUTILUS_OPEN_ANY_TERMINAL_COPR="${NAUTILUS_OPEN_ANY_TERMINAL_COPR:-monkeygold/nautilus-open-any-terminal}"
NAUTILUS_TERMINAL="${NAUTILUS_TERMINAL:-alacritty}"
MCMOJAVE_CURSORS_REPO="${MCMOJAVE_CURSORS_REPO:-https://github.com/vinceliuice/McMojave-cursors}"
MCMOJAVE_CURSORS_DIR="${MCMOJAVE_CURSORS_DIR:-$HOME/.cache/fedora-niri-setup/McMojave-cursors}"
MCMOJAVE_CURSOR_THEME="${MCMOJAVE_CURSOR_THEME:-McMojave-cursors}"
LSFG_VK_RELEASE_API="${LSFG_VK_RELEASE_API:-https://api.github.com/repos/PancakeTAS/lsfg-vk/releases/latest}"
LSFG_VK_ASSET_REGEX="${LSFG_VK_ASSET_REGEX:-lsfg-vk-.*(linux|x86_64).*\\.tar\\.xz$}"
POLARIS_BASE_URL="${POLARIS_BASE_URL:-https://github.com/papi-ux/polaris/releases/latest/download}"
NOCTALIA_CONFIG_FILE="${NOCTALIA_CONFIG_FILE:-settings.toml}"
NOCTALIA_CONFIG_RELATIVE_DIR="${NOCTALIA_CONFIG_RELATIVE_DIR:-.local/state/noctalia}"
NOCTALIA_WALLPAPER_FILE="${NOCTALIA_WALLPAPER_FILE:-13.png}"
NOCTALIA_WALLPAPER_MONITORS="${NOCTALIA_WALLPAPER_MONITORS:-DP-3}"
GREETD_USER="${GREETD_USER:-greeter}"
NOCTALIA_GREETER_SESSION_BIN="${NOCTALIA_GREETER_SESSION_BIN:-}"

XKB_LAYOUT="${XKB_LAYOUT:-se}"
GTK_COLOR_SCHEME="${GTK_COLOR_SCHEME:-prefer-dark}"
GTK_THEME_NAME="${GTK_THEME_NAME:-Adwaita-dark}"
GTK_APPLICATION_PREFER_DARK="${GTK_APPLICATION_PREFER_DARK:-1}"
GTK_CURSOR_THEME="${GTK_CURSOR_THEME:-$MCMOJAVE_CURSOR_THEME}"
WALLPAPER_PARENT_DIR="${WALLPAPER_PARENT_DIR:-}"
WALLPAPER_SUBDIR="${WALLPAPER_SUBDIR:-wallpapers}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_FILE:-$HOME/fedora-niri-setup-$TIMESTAMP.log}"
USER_BACKUP_ROOT="${USER_BACKUP_ROOT:-$HOME/.local/share/fedora-niri-setup/backups/$TIMESTAMP}"
SYSTEM_BACKUP_ROOT="${SYSTEM_BACKUP_ROOT:-/var/backups/fedora-niri-setup/$TIMESTAMP}"

TARGET_HOME="$HOME"
DNF_BIN=""
STEP_COUNT=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_BLUE=$'\033[1;34m'
  COLOR_GREEN=$'\033[1;32m'
  COLOR_YELLOW=$'\033[1;33m'
  COLOR_RED=$'\033[1;31m'
  COLOR_DIM=$'\033[2m'
else
  COLOR_RESET=""
  COLOR_BLUE=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_DIM=""
fi

declare -a CHANGES=()
declare -a WARNINGS=()
declare -a USER_BACKUPS=()
declare -a SYSTEM_BACKUPS=()

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'die "Setup failed on or near line $LINENO. Review $LOG_FILE, fix the reported problem, then re-run the script."' ERR

section() {
  STEP_COUNT=$((STEP_COUNT + 1))
  printf '\n%s+--[%02d] %s%s\n' "$COLOR_BLUE" "$STEP_COUNT" "$*" "$COLOR_RESET"
  printf '%s|%s\n' "$COLOR_DIM" "$COLOR_RESET"
}

log() {
  printf '%s[%s]%s %s\n' "$COLOR_GREEN" "$(date '+%H:%M:%S')" "$COLOR_RESET" "$*"
}

warn() {
  WARNINGS+=("$*")
  printf '%s[%s] WARNING:%s %s\n' "$COLOR_YELLOW" "$(date '+%H:%M:%S')" "$COLOR_RESET" "$*" >&2
}

die() {
  printf '%s[%s] ERROR:%s %s\n' "$COLOR_RED" "$(date '+%H:%M:%S')" "$COLOR_RESET" "$*" >&2
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

safe_rm_rf() {
  local path="$1"
  [[ -n "$path" && "$path" != "/" ]] || die "Refusing to remove unsafe path: $path"

  case "$path" in
    "$TARGET_HOME"/*)
      run_as_user rm -rf -- "$path"
      ;;
    /tmp/*|/var/tmp/*|/private/tmp/*|/private/var/tmp/*)
      rm -rf -- "$path"
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

  run_sudo "$DNF_BIN" "${args[@]}" "${packages[@]}"
}

dnf_install_optional() {
  if dnf_install "$@"; then
    return 0
  fi

  warn "Could not install optional package set: $*"
  return 1
}

enable_copr_repo() {
  local copr="$1"
  local label="${2:-$copr}"
  local repo_owner="${copr%%/*}"
  local repo_name="${copr#*/}"
  local repo_glob="/etc/yum.repos.d/*${repo_owner}*${repo_name}*.repo"

  dnf_install dnf-plugins-core

  if compgen -G "$repo_glob" >/dev/null; then
    log "COPR $copr appears to be enabled."
    return 0
  fi

  log "Enabling COPR $copr for $label."
  run_sudo "$DNF_BIN" copr enable -y "$copr"
  record_change "Enabled COPR $copr."
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
    flatpak
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
    gnome-keyring
    seahorse
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
  )

  if [[ -n "$EXTRA_FEDORA_PACKAGES" ]]; then
    local extra_packages=()
    read -r -a extra_packages <<<"$EXTRA_FEDORA_PACKAGES"
    packages+=("${extra_packages[@]}")
  fi

  log "Installing Fedora packages with $DNF_BIN."
  dnf_install "${packages[@]}"
  record_change "Installed or verified Fedora packages for a basic Niri desktop."
}

enable_flathub() {
  [[ "$ENABLE_FLATHUB" == "1" ]] || {
    log "Flathub enablement is disabled."
    return 0
  }

  have_command flatpak || {
    warn "flatpak is not available; skipping Flathub setup."
    return 1
  }

  if flatpak remotes --system | awk '{ print $1 }' | grep -Fxq flathub; then
    log "Flathub system remote is already enabled."
  else
    log "Enabling Flathub system remote."
    run_sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    record_change "Enabled Flathub system remote."
  fi
}

install_flatpak_app() {
  local app_id="$1"
  local label="$2"

  have_command flatpak || {
    warn "flatpak is not available; skipping $label."
    return 1
  }

  if flatpak info --system "$app_id" >/dev/null 2>&1; then
    log "$label is already installed as a system Flatpak."
    return 0
  fi

  log "Installing $label from Flathub."
  if [[ "$ASSUME_YES" == "1" ]]; then
    run_sudo flatpak install --system -y flathub "$app_id"
  else
    run_sudo flatpak install --system flathub "$app_id"
  fi
  record_change "Installed $label from Flathub."
}

install_flatpak_apps() {
  [[ "$INSTALL_STEAM" == "1" || "$INSTALL_BITWARDEN" == "1" ]] || return 0

  enable_flathub || return 0

  if [[ "$INSTALL_STEAM" == "1" ]]; then
    install_flatpak_app com.valvesoftware.Steam Steam || warn "Steam Flatpak installation failed."
  fi

  if [[ "$INSTALL_BITWARDEN" == "1" ]]; then
    install_flatpak_app com.bitwarden.desktop Bitwarden || warn "Bitwarden Flatpak installation failed."
  fi
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

  local theme_dirs=()
  shopt -s nullglob
  theme_dirs=("$MCMOJAVE_CURSORS_DIR"/dist/*)
  shopt -u nullglob

  ((${#theme_dirs[@]})) || {
    warn "No cursor themes found in $MCMOJAVE_CURSORS_DIR/dist; skipping McMojave cursor install."
    return 0
  }

  run_as_user mkdir -p "$TARGET_HOME/.local/share/icons"

  local theme_dir
  for theme_dir in "${theme_dirs[@]}"; do
    [[ -d "$theme_dir" ]] || continue
    replace_user_path_with_dir "$theme_dir" "$TARGET_HOME/.local/share/icons/$(basename "$theme_dir")"
  done

  record_change "Installed McMojave cursor themes to $TARGET_HOME/.local/share/icons."
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

  if run_as_user gsettings writable com.github.stunkymonkey.nautilus-open-any-terminal terminal >/dev/null 2>&1; then
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

install_lsfg_vk() {
  [[ "$INSTALL_LSFG_VK" == "1" ]] || {
    log "LSFG-VK installation is disabled."
    return 0
  }

  local asset_url
  if ! asset_url="$(github_latest_asset_url "$LSFG_VK_RELEASE_API" "$LSFG_VK_ASSET_REGEX")" || [[ -z "$asset_url" ]]; then
    warn "Could not find a matching LSFG-VK release asset."
    return 0
  fi

  local downloads_dir="$TARGET_HOME/.cache/fedora-niri-setup/downloads"
  local archive="$downloads_dir/$(basename "$asset_url")"

  log "Downloading LSFG-VK from $asset_url."
  if ! download_as_user "$asset_url" "$archive"; then
    warn "Could not download LSFG-VK."
    return 0
  fi

  run_as_user mkdir -p "$TARGET_HOME/.local"
  if ! run_as_user tar -xJf "$archive" -C "$TARGET_HOME/.local"; then
    warn "Could not extract LSFG-VK archive."
    return 0
  fi

  record_change "Installed LSFG-VK into $TARGET_HOME/.local."
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
}

install_default_apps() {
  install_vscode
  install_flatpak_apps
  install_mcmojave_cursors
  install_nautilus_open_any_terminal
  install_lsfg_vk
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

  run_as_user mkdir -p "$(dirname "$CONFIG_REPO_DIR")"

  if [[ -d "$CONFIG_REPO_DIR/.git" ]]; then
    local current_url
    current_url="$(run_as_user git -C "$CONFIG_REPO_DIR" config --get remote.origin.url || true)"
    if [[ "$current_url" != "$CONFIG_REPO_URL" ]]; then
      warn "$CONFIG_REPO_DIR is a git repository with origin $current_url, not $CONFIG_REPO_URL. Backing it up and cloning fresh."
      backup_user_path "$CONFIG_REPO_DIR"
      safe_rm_rf "$CONFIG_REPO_DIR"
      run_as_user git clone --branch "$CONFIG_REPO_BRANCH" "$CONFIG_REPO_URL" "$CONFIG_REPO_DIR"
    else
      log "Updating config repository at $CONFIG_REPO_DIR."
      run_as_user git -C "$CONFIG_REPO_DIR" fetch --prune
      run_as_user git -C "$CONFIG_REPO_DIR" checkout -f "$CONFIG_REPO_BRANCH"
      run_as_user git -C "$CONFIG_REPO_DIR" reset --hard "origin/$CONFIG_REPO_BRANCH"
    fi
  elif [[ -e "$CONFIG_REPO_DIR" ]]; then
    warn "$CONFIG_REPO_DIR exists but is not a git repository. Backing it up and cloning fresh."
    backup_user_path "$CONFIG_REPO_DIR"
    safe_rm_rf "$CONFIG_REPO_DIR"
    run_as_user git clone --branch "$CONFIG_REPO_BRANCH" "$CONFIG_REPO_URL" "$CONFIG_REPO_DIR"
  else
    log "Cloning config repository to $CONFIG_REPO_DIR."
    run_as_user git clone --branch "$CONFIG_REPO_BRANCH" "$CONFIG_REPO_URL" "$CONFIG_REPO_DIR"
  fi

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

ensure_niri_autostarts_noctalia() {
  local niri_dir="$TARGET_HOME/.config/niri"
  local autostart_file="$niri_dir/cfg/autostart.kdl"
  local fallback_file="$niri_dir/config.kdl"
  local target_file=""

  if [[ -f "$autostart_file" ]]; then
    target_file="$autostart_file"
  elif [[ -f "$fallback_file" ]]; then
    target_file="$fallback_file"
    warn "No $autostart_file found; adding Noctalia autostart to $fallback_file instead."
  else
    warn "No Niri config file found; could not add Noctalia autostart."
    return 0
  fi

  if grep -Eq '^[[:space:]]*spawn-at-startup[[:space:]]+"noctalia"' "$target_file"; then
    log "Niri already autostarts Noctalia in $target_file."
    return 0
  fi

  backup_user_path "$target_file"
  local tmp
  tmp="$(mktemp)"
  grep -Ev \
    '^[[:space:]]*spawn-at-startup[[:space:]]+.*(noctalia-shell|noctalia-qs|"qs"[[:space:]]+"-c"[[:space:]]+"noctalia|quickshell.*noctalia)' \
    "$target_file" >"$tmp"

  cat >>"$tmp" <<'EOF'

// Noctalia v5
spawn-at-startup "noctalia"
EOF

  chmod 0644 "$tmp"
  run_as_user install -m 0644 "$tmp" "$target_file"
  rm -f "$tmp"

  if have_command niri; then
    run_as_user niri validate -c "$niri_dir/config.kdl" >/dev/null 2>&1 || warn "Niri config validation failed after adding Noctalia autostart."
  fi

  record_change "Configured Niri to autostart Noctalia v5."
}

configure_user_environment() {
  write_user_file "$TARGET_HOME/.config/environment.d/10-fedora-niri-setup.conf" 0644 <<EOF
XDG_CURRENT_DESKTOP=niri
XDG_SESSION_DESKTOP=niri
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland;xcb
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
XKB_DEFAULT_LAYOUT=$XKB_LAYOUT
EOF

  if have_command xdg-user-dirs-update; then
    run_as_user xdg-user-dirs-update || warn "xdg-user-dirs-update failed for $TARGET_USER."
  fi

  record_change "Configured basic user environment for Niri and Wayland apps."
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

  if run_as_user gsettings writable org.gnome.desktop.interface color-scheme >/dev/null 2>&1; then
    run_as_user gsettings set org.gnome.desktop.interface color-scheme "$GTK_COLOR_SCHEME" || warn "Could not set GNOME color-scheme."
  fi

  if run_as_user gsettings writable org.gnome.desktop.interface gtk-theme >/dev/null 2>&1; then
    run_as_user gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" || warn "Could not set GNOME gtk-theme."
  fi

  if run_as_user gsettings writable org.gnome.desktop.interface cursor-theme >/dev/null 2>&1; then
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

  printf '\nSetup summary\n'
  printf '=============\n'
  printf 'Log file: %s\n' "$LOG_FILE"
  printf 'User backups: %s\n' "$USER_BACKUP_ROOT"
  printf 'System backups: %s\n' "$SYSTEM_BACKUP_ROOT"

  if ((${#CHANGES[@]})); then
    printf '\nChanges made or verified:\n'
    for item in "${CHANGES[@]}"; do
      printf ' - %s\n' "$item"
    done
  fi

  if ((${#WARNINGS[@]})); then
    printf '\nWarnings:\n'
    for item in "${WARNINGS[@]}"; do
      printf ' - %s\n' "$item"
    done
  fi
}

main() {
  section "Fedora Niri setup"
  require_fedora
  resolve_target_user
  prepare_runtime

  section "Base packages"
  install_fedora_packages

  section "Default apps"
  install_default_apps

  section "Noctalia"
  install_noctalia_packages

  section "Repo configs"
  clone_or_update_config_repo
  verify_config_source
  install_user_configs
  ensure_niri_autostarts_noctalia

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
