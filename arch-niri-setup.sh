#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_REPO_URL="${CONFIG_REPO_URL:-https://github.com/socawi-ai/linux-niri}"
CONFIG_REPO_DIR_WAS_SET=0
[[ -n "${CONFIG_REPO_DIR+x}" ]] && CONFIG_REPO_DIR_WAS_SET=1
CONFIG_REPO_DIR="${CONFIG_REPO_DIR:-$HOME/.cache/arch-niri-setup/linux-niri}"

AUR_PACKAGE_PARU="${AUR_PACKAGE_PARU:-paru}"
AUR_PACKAGE_NOCTALIA="${AUR_PACKAGE_NOCTALIA:-noctalia-git}"
AUR_PACKAGE_NOCTALIA_GREETER="${AUR_PACKAGE_NOCTALIA_GREETER:-noctalia-greeter-git}"
AUR_PACKAGE_NAUTILUS_OPEN_ANY_TERMINAL="${AUR_PACKAGE_NAUTILUS_OPEN_ANY_TERMINAL:-nautilus-open-any-terminal-git}"
AUR_PACKAGE_MCMOJAVE_CURSORS="${AUR_PACKAGE_MCMOJAVE_CURSORS:-mcmojave-cursors}"
AUR_PACKAGE_VSCODE="${AUR_PACKAGE_VSCODE:-visual-studio-code-bin}"
AUR_PACKAGE_LSFG_VK="${AUR_PACKAGE_LSFG_VK:-lsfg-vk-git}"

NOCTALIA_GREETER_SESSION_BIN="${NOCTALIA_GREETER_SESSION_BIN:-/usr/bin/noctalia-greeter-session}"
NOCTALIA_GREETER_COMMAND="${NOCTALIA_GREETER_COMMAND:-$NOCTALIA_GREETER_SESSION_BIN -- --session niri}"
GREETD_USER="${GREETD_USER:-greeter}"
PLYMOUTH_THEME="${PLYMOUTH_THEME:-spinner}"
LIMINE_CONFIG="${LIMINE_CONFIG:-/boot/limine/limine.conf}"
LIMINE_ARCH_ENTRY_MATCH="${LIMINE_ARCH_ENTRY_MATCH:-Arch Linux}"
LIMINE_DEFAULT_ENTRY="${LIMINE_DEFAULT_ENTRY:-}"
POLARIS_PACKAGE_URL="${POLARIS_PACKAGE_URL:-https://github.com/papi-ux/polaris/releases/latest/download/Polaris-arch-x86_64.pkg.tar.zst}"
POLARIS_ENCODER="${POLARIS_ENCODER:-nvenc}"
POLARIS_TRUSTED_SUBNETS="${POLARIS_TRUSTED_SUBNETS:-[\"10.0.0.0/24\"]}"
POLARIS_MAX_SESSIONS="${POLARIS_MAX_SESSIONS:-2}"

ENABLE_GREETD="${ENABLE_GREETD:-1}"
ENABLE_PLYMOUTH="${ENABLE_PLYMOUTH:-1}"
ENABLE_SNAPSHOTS="${ENABLE_SNAPSHOTS:-1}"
ENABLE_POLARIS="${ENABLE_POLARIS:-1}"
ENABLE_POLARIS_USER_SERVICE="${ENABLE_POLARIS_USER_SERVICE:-1}"
ENABLE_QUIET_KERNEL_ARG="${ENABLE_QUIET_KERNEL_ARG:-1}"
DISABLE_CONFLICTING_DISPLAY_MANAGERS="${DISABLE_CONFLICTING_DISPLAY_MANAGERS:-1}"
INSTALL_STEAM="${INSTALL_STEAM:-1}"
ASSUME_YES="${ASSUME_YES:-0}"

SWEDISH_LOCALE="${SWEDISH_LOCALE:-sv_SE.UTF-8}"
CONSOLE_KEYMAP="${CONSOLE_KEYMAP:-sv-latin1}"
XKB_LAYOUT="${XKB_LAYOUT:-se}"
CURSOR_THEME="${CURSOR_THEME:-McMojave-cursors}"
CURSOR_SIZE="${CURSOR_SIZE:-24}"
WALLPAPER_PARENT_DIR="${WALLPAPER_PARENT_DIR:-}"
WALLPAPER_SUBDIR="${WALLPAPER_SUBDIR:-wallpapers}"
NOCTALIA_WALLPAPER_FILE="${NOCTALIA_WALLPAPER_FILE:-10.jpg}"
NOCTALIA_CONFIG_FILE="${NOCTALIA_CONFIG_FILE:-settings.toml}"
NOCTALIA_CONFIG_RELATIVE_DIR="${NOCTALIA_CONFIG_RELATIVE_DIR:-.local/state/noctalia}"
GTK_COLOR_SCHEME="${GTK_COLOR_SCHEME:-prefer-dark}"
GTK_THEME_NAME="${GTK_THEME_NAME:-Adwaita-dark}"
GTK_APPLICATION_PREFER_DARK="${GTK_APPLICATION_PREFER_DARK:-1}"

EXTRA_OFFICIAL_PACKAGES="${EXTRA_OFFICIAL_PACKAGES:-}"
EXTRA_AUR_PACKAGES="${EXTRA_AUR_PACKAGES:-}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE_WAS_SET=0
USER_BACKUP_ROOT_WAS_SET=0
[[ -n "${LOG_FILE+x}" ]] && LOG_FILE_WAS_SET=1
[[ -n "${USER_BACKUP_ROOT+x}" ]] && USER_BACKUP_ROOT_WAS_SET=1
LOG_FILE="${LOG_FILE:-$HOME/arch-niri-setup-$TIMESTAMP.log}"
USER_BACKUP_ROOT="${USER_BACKUP_ROOT:-$HOME/.local/share/arch-niri-setup/backups/$TIMESTAMP}"
SYSTEM_BACKUP_ROOT="${SYSTEM_BACKUP_ROOT:-/var/backups/arch-niri-setup/$TIMESTAMP}"

TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
TARGET_HOME="$HOME"

declare -a CHANGES=()
declare -a WARNINGS=()
declare -a SYSTEM_BACKUPS=()
declare -a USER_BACKUPS=()

COLOR_ENABLED=0
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  COLOR_ENABLED=1
fi

if [[ "$COLOR_ENABLED" == "1" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_BLUE=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
  C_CYAN=""
fi

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'die "Setup failed on or near line $LINENO. Review $LOG_FILE, fix the reported problem, then re-run the script."' ERR

log() {
  printf '%s[%s]%s %s%s%s\n' "$C_DIM" "$(date '+%H:%M:%S')" "$C_RESET" "$C_BLUE" "$*" "$C_RESET"
}

warn() {
  WARNINGS+=("$*")
  printf '%s[%s]%s %sWARNING:%s %s\n' "$C_DIM" "$(date '+%H:%M:%S')" "$C_RESET" "$C_YELLOW" "$C_RESET" "$*" >&2
}

die() {
  printf '%s[%s]%s %sERROR:%s %s\n' "$C_DIM" "$(date '+%H:%M:%S')" "$C_RESET" "$C_RED" "$C_RESET" "$*" >&2
  exit 1
}

record_change() {
  CHANGES+=("$*")
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

have_command() {
  command -v "$1" >/dev/null 2>&1
}

require_tty_for_prompt() {
  [[ -r /dev/tty && -w /dev/tty ]] || die "A decision is required, but no interactive terminal is available. Re-run from a terminal or set ASSUME_YES=1."
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local suffix
  local answer

  if [[ "$ASSUME_YES" == "1" ]]; then
    case "$default" in
      y|Y)
        log "ASSUME_YES=1: using default yes for prompt: $prompt"
        return 0
        ;;
      *)
        log "ASSUME_YES=1: using default no for prompt: $prompt"
        return 1
        ;;
    esac
  fi

  require_tty_for_prompt
  case "$default" in
    y|Y) suffix="[Y/n]" ;;
    *) suffix="[y/N]" ;;
  esac

  while true; do
    printf '%s%s%s %s%s%s ' "$C_CYAN" "$prompt" "$C_RESET" "$C_DIM" "$suffix" "$C_RESET" >/dev/tty
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

  require_tty_for_prompt
  if [[ -n "$default" ]]; then
    printf '%s%s%s %s[%s]%s: ' "$C_CYAN" "$prompt" "$C_RESET" "$C_DIM" "$default" "$C_RESET" >/dev/tty
  else
    printf '%s%s%s: ' "$C_CYAN" "$prompt" "$C_RESET" >/dev/tty
  fi
  IFS= read -r answer </dev/tty
  printf '%s\n' "${answer:-$default}"
}

print_welcome() {
  if [[ "$ASSUME_YES" == "1" ]]; then
    log "Running unattended with script defaults and pre-set environment values."
    return 0
  fi

  require_tty_for_prompt
  cat >/dev/tty <<'EOF'

Arch Niri guided installer
==========================
This will install packages, copy user configs, configure greetd, locale,
Plymouth, cursor defaults, Fish, and optional Steam/Snapper integration.

Press Enter to accept a shown default. You can stop with Ctrl+C before package
installation starts.

EOF
}

ask_existing_user() {
  local default_user="$1"
  local chosen_user

  while true; do
    chosen_user="$(ask_value "Target username for user configs" "$default_user")"
    if getent passwd "$chosen_user" >/dev/null; then
      printf '%s\n' "$chosen_user"
      return 0
    fi
    warn "User '$chosen_user' does not exist on this install."
  done
}

configure_guided_install() {
  print_welcome

  if [[ "$ASSUME_YES" != "1" ]]; then
    TARGET_USER="$(ask_existing_user "$TARGET_USER")"
    INSTALL_STEAM="$(ask_yes_no "Install Steam and enable multilib if needed?" "$([[ "$INSTALL_STEAM" == "1" ]] && printf y || printf n)" && printf 1 || printf 0)"
    ENABLE_GREETD="$(ask_yes_no "Configure greetd with Noctalia Greeter?" "$([[ "$ENABLE_GREETD" == "1" ]] && printf y || printf n)" && printf 1 || printf 0)"
    ENABLE_PLYMOUTH="$(ask_yes_no "Configure Plymouth boot splash?" "$([[ "$ENABLE_PLYMOUTH" == "1" ]] && printf y || printf n)" && printf 1 || printf 0)"
    ENABLE_SNAPSHOTS="$(ask_yes_no "Configure Snapper pacman hooks when Snapper is already set up?" "$([[ "$ENABLE_SNAPSHOTS" == "1" ]] && printf y || printf n)" && printf 1 || printf 0)"
    ENABLE_POLARIS="$(ask_yes_no "Install and configure Polaris game streaming host?" "$([[ "$ENABLE_POLARIS" == "1" ]] && printf y || printf n)" && printf 1 || printf 0)"
    if [[ "$ENABLE_POLARIS" == "1" ]]; then
      POLARIS_ENCODER="$(ask_value "Polaris encoder (nvenc, vaapi, or software)" "$POLARIS_ENCODER")"
      POLARIS_TRUSTED_SUBNETS="$(ask_value "Polaris trusted_subnets value" "$POLARIS_TRUSTED_SUBNETS")"
      ENABLE_POLARIS_USER_SERVICE="$(ask_yes_no "Enable and start Polaris user service?" "$([[ "$ENABLE_POLARIS_USER_SERVICE" == "1" ]] && printf y || printf n)" && printf 1 || printf 0)"
    fi
    DISABLE_CONFLICTING_DISPLAY_MANAGERS="$(ask_yes_no "Offer to disable display managers that conflict with greetd?" "$([[ "$DISABLE_CONFLICTING_DISPLAY_MANAGERS" == "1" ]] && printf y || printf n)" && printf 1 || printf 0)"
  fi
}

require_normal_user() {
  [[ "$EUID" -ne 0 ]] || die "Run this script as your normal user, not directly as root."
  [[ -f /etc/arch-release ]] || die "This script is intended for Arch Linux."
}

resolve_target_user() {
  local passwd_home
  passwd_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$passwd_home" ]] || die "Could not determine home directory for $TARGET_USER."
  TARGET_HOME="$passwd_home"

  if [[ "$CONFIG_REPO_DIR_WAS_SET" == "0" ]]; then
    CONFIG_REPO_DIR="$TARGET_HOME/.cache/arch-niri-setup/linux-niri"
  fi
  if [[ "$USER_BACKUP_ROOT_WAS_SET" == "0" ]]; then
    USER_BACKUP_ROOT="$TARGET_HOME/.local/share/arch-niri-setup/backups/$TIMESTAMP"
  fi
  if [[ "$LOG_FILE_WAS_SET" == "0" && "$HOME" == "$TARGET_HOME" ]]; then
    LOG_FILE="$TARGET_HOME/arch-niri-setup-$TIMESTAMP.log"
  fi

  [[ "$HOME" == "$TARGET_HOME" ]] || warn "HOME is $HOME, but $TARGET_USER's passwd home is $TARGET_HOME. User config will use $TARGET_HOME."
  log "Target user: $TARGET_USER"
  log "Target home: $TARGET_HOME"
}

prepare_runtime() {
  run_as_user mkdir -p "$USER_BACKUP_ROOT"
  run_sudo install -d -m 0755 "$SYSTEM_BACKUP_ROOT"
  log "Log file: $LOG_FILE"
  log "User backups: $USER_BACKUP_ROOT"
  log "System backups: $SYSTEM_BACKUP_ROOT"
  run_sudo -v
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

replace_user_path_with_dir() {
  local src="$1"
  local dest="$2"
  [[ -d "$src" ]] || die "Expected directory $src."
  backup_user_path "$dest"
  safe_rm_rf "$dest"
  run_as_user mkdir -p "$(dirname "$dest")"
  run_as_user cp -a "$src" "$dest"
  record_change "Installed $(basename "$dest") from $src to $dest"
}

replace_user_file() {
  local src="$1"
  local dest="$2"
  [[ -f "$src" ]] || die "Expected file $src."
  backup_user_path "$dest"
  run_as_user rm -f "$dest"
  run_as_user mkdir -p "$(dirname "$dest")"
  run_as_user cp -a "$src" "$dest"
  record_change "Installed file $dest from $src"
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

append_line_if_missing_system() {
  local path="$1"
  local line="$2"
  run_sudo touch "$path"
  if ! grep -Fxq "$line" "$path"; then
    backup_system_path "$path"
    printf '%s\n' "$line" | run_sudo tee -a "$path" >/dev/null
    record_change "Added required line to $path: $line"
  fi
}

enable_multilib() {
  [[ "$INSTALL_STEAM" == "1" ]] || {
    log "Steam installation is disabled; leaving multilib unchanged."
    return 0
  }

  if awk '
    /^[[:space:]]*\[multilib\][[:space:]]*$/ {
      in_multilib = 1
      next
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      in_multilib = 0
    }
    in_multilib && /^[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman.d\/mirrorlist[[:space:]]*$/ {
      found = 1
    }
    END { exit found ? 0 : 1 }
  ' /etc/pacman.conf; then
    log "multilib is already enabled."
    return 0
  fi

  if ! ask_yes_no "Steam requires the pacman multilib repository. Enable multilib now?" y; then
    INSTALL_STEAM=0
    warn "Steam installation was skipped because multilib was not enabled."
    return 0
  fi

  backup_system_path /etc/pacman.conf
  local tmp
  tmp="$(mktemp)"
  awk '
    BEGIN { changed = 0; want_include = 0 }
    /^[[:space:]]*#[[:space:]]*\[multilib\][[:space:]]*$/ {
      print "[multilib]";
      changed = 1;
      want_include = 1;
      next;
    }
    want_include && /^[[:space:]]*#[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman.d\/mirrorlist[[:space:]]*$/ {
      print "Include = /etc/pacman.d/mirrorlist";
      want_include = 0;
      next;
    }
    { print }
    END {
      if (want_include) {
        print "Include = /etc/pacman.d/mirrorlist";
      } else if (!changed) {
        print "";
        print "[multilib]";
        print "Include = /etc/pacman.d/mirrorlist";
      }
    }
  ' /etc/pacman.conf >"$tmp"
  run_sudo install -m 0644 "$tmp" /etc/pacman.conf
  rm -f "$tmp"
  record_change "Enabled pacman multilib repository for Steam."
  log "Refreshing package databases after pacman.conf change."
  run_sudo pacman -Sy --noconfirm
}

append_steam_gpu_packages() {
  local -n package_list="$1"
  local has_amd=0
  local has_intel=0
  local has_nvidia=0
  local vendor_file
  local vendor

  for vendor_file in /sys/class/drm/card*/device/vendor; do
    [[ -r "$vendor_file" ]] || continue
    vendor="$(<"$vendor_file")"
    case "$vendor" in
      0x1002) has_amd=1 ;;
      0x8086) has_intel=1 ;;
      0x10de) has_nvidia=1 ;;
    esac
  done

  if [[ "$has_amd" == "1" ]]; then
    package_list+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon)
  fi

  if [[ "$has_intel" == "1" ]]; then
    package_list+=(mesa lib32-mesa vulkan-intel lib32-vulkan-intel)
  fi

  if [[ "$has_nvidia" == "1" ]]; then
    package_list+=(nvidia-utils lib32-nvidia-utils)
  fi

  if [[ "$has_amd$has_intel$has_nvidia" == "000" ]]; then
    warn "Could not detect AMD, Intel, or NVIDIA GPU hardware. Steam may still ask pacman to choose Vulkan/OpenGL providers."
  fi
}

install_official_packages() {
  local packages=(
    base-devel
    curl
    git
    github-cli
    niri
    greetd
    alacritty
    ttf-jetbrains-mono
    fish
    firefox
    xwayland-satellite
    nautilus
    gnome-software
    bitwarden
    xdg-user-dirs
    xdg-utils
    xdg-desktop-portal
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
    gnome-keyring
    seahorse
    file-roller
    avahi
    gvfs
    gvfs-smb
    gvfs-mtp
    gvfs-afc
    nss-mdns
    loupe
    gnome-text-editor
    gnome-calculator
    gnome-disk-utility
    gnome-system-monitor
    dbus
    dconf
    libsecret
    gtk3
    gtk4
    qt5-wayland
    qt6-wayland
    pipewire
    wireplumber
    pipewire-pulse
    pipewire-alsa
    pipewire-jack
  )

  if [[ "$INSTALL_STEAM" == "1" ]]; then
    append_steam_gpu_packages packages
    packages+=(steam)
  fi

  if [[ "$ENABLE_PLYMOUTH" == "1" ]]; then
    packages+=(plymouth)
  fi

  if [[ "$ENABLE_SNAPSHOTS" == "1" ]]; then
    packages+=(snapper)
  fi

  if [[ -n "$EXTRA_OFFICIAL_PACKAGES" ]]; then
    local extra_packages=()
    read -r -a extra_packages <<<"$EXTRA_OFFICIAL_PACKAGES"
    packages+=("${extra_packages[@]}")
  fi

  local deduped_packages=()
  local package
  declare -A seen_packages=()
  for package in "${packages[@]}"; do
    if [[ -z "${seen_packages[$package]+x}" ]]; then
      deduped_packages+=("$package")
      seen_packages["$package"]=1
    fi
  done
  packages=("${deduped_packages[@]}")

  log "Installing official packages with pacman."
  local pacman_args=(-S --needed)
  if [[ "$ASSUME_YES" == "1" ]]; then
    pacman_args+=(--noconfirm)
  fi
  run_sudo pacman "${pacman_args[@]}" "${packages[@]}"
  record_change "Installed or verified official pacman packages."
}

install_paru_if_missing() {
  if have_command paru; then
    log "paru is already installed."
    return 0
  fi

  log "Installing paru from the AUR using makepkg."
  local build_dir
  build_dir="$(run_as_user mktemp -d)"
  run_as_user git clone "https://aur.archlinux.org/${AUR_PACKAGE_PARU}.git" "$build_dir/$AUR_PACKAGE_PARU"
  (
    cd "$build_dir/$AUR_PACKAGE_PARU"
    local makepkg_args=(-si --needed)
    if [[ "$ASSUME_YES" == "1" ]]; then
      makepkg_args+=(--noconfirm)
    fi
    run_as_user makepkg "${makepkg_args[@]}"
  )
  safe_rm_rf "$build_dir"
  have_command paru || die "paru installation finished, but paru is still not in PATH."
  record_change "Installed paru from the AUR."
}

install_aur_packages() {
  local packages=(
    "$AUR_PACKAGE_NOCTALIA"
    "$AUR_PACKAGE_NOCTALIA_GREETER"
    "$AUR_PACKAGE_NAUTILUS_OPEN_ANY_TERMINAL"
    "$AUR_PACKAGE_MCMOJAVE_CURSORS"
    "$AUR_PACKAGE_VSCODE"
    "$AUR_PACKAGE_LSFG_VK"
  )

  if [[ -n "$EXTRA_AUR_PACKAGES" ]]; then
    local extra_packages=()
    read -r -a extra_packages <<<"$EXTRA_AUR_PACKAGES"
    packages+=("${extra_packages[@]}")
  fi

  log "Installing AUR packages with paru."
  local paru_args=(-S --needed)
  if [[ "$ASSUME_YES" == "1" ]]; then
    paru_args+=(--noconfirm)
  fi
  run_as_user paru "${paru_args[@]}" "${packages[@]}"
  record_change "Installed or verified AUR packages: ${packages[*]}"
}

download_file() {
  local url="$1"
  local dest="$2"

  if have_command curl; then
    curl -fL "$url" -o "$dest"
  elif have_command wget; then
    wget -O "$dest" "$url"
  else
    die "Neither curl nor wget is available to download $url."
  fi
}

upsert_polaris_config() {
  local path="$TARGET_HOME/.config/polaris/polaris.conf"
  local tmp
  run_as_user mkdir -p "$(dirname "$path")"
  backup_user_path "$path"
  tmp="$(mktemp)"

  if [[ -f "$path" ]]; then
    awk \
      -v trusted_subnets="$POLARIS_TRUSTED_SUBNETS" \
      -v encoder="$POLARIS_ENCODER" \
      -v max_sessions="$POLARIS_MAX_SESSIONS" '
      function emit_missing() {
        if (!seen_headless) print "headless_mode = enabled"
        if (!seen_cage) print "linux_use_cage_compositor = enabled"
        if (!seen_gpu_native) print "linux_prefer_gpu_native_capture = disabled"
        if (!seen_trusted) print "trusted_subnets = " trusted_subnets
        if (!seen_encoder) print "encoder = " encoder
        if (!seen_bitrate) print "adaptive_bitrate_enabled = enabled"
        if (!seen_sessions) print "max_sessions = " max_sessions
      }
      /^[[:space:]]*headless_mode[[:space:]]*=/ {
        print "headless_mode = enabled"
        seen_headless = 1
        next
      }
      /^[[:space:]]*linux_use_cage_compositor[[:space:]]*=/ {
        print "linux_use_cage_compositor = enabled"
        seen_cage = 1
        next
      }
      /^[[:space:]]*linux_prefer_gpu_native_capture[[:space:]]*=/ {
        print "linux_prefer_gpu_native_capture = disabled"
        seen_gpu_native = 1
        next
      }
      /^[[:space:]]*trusted_subnets[[:space:]]*=/ {
        print "trusted_subnets = " trusted_subnets
        seen_trusted = 1
        next
      }
      /^[[:space:]]*encoder[[:space:]]*=/ {
        print "encoder = " encoder
        seen_encoder = 1
        next
      }
      /^[[:space:]]*adaptive_bitrate_enabled[[:space:]]*=/ {
        print "adaptive_bitrate_enabled = enabled"
        seen_bitrate = 1
        next
      }
      /^[[:space:]]*max_sessions[[:space:]]*=/ {
        print "max_sessions = " max_sessions
        seen_sessions = 1
        next
      }
      { print }
      END { emit_missing() }
    ' "$path" >"$tmp"
  else
    cat >"$tmp" <<EOF
headless_mode = enabled
linux_use_cage_compositor = enabled
linux_prefer_gpu_native_capture = disabled
trusted_subnets = $POLARIS_TRUSTED_SUBNETS
encoder = $POLARIS_ENCODER
adaptive_bitrate_enabled = enabled
max_sessions = $POLARIS_MAX_SESSIONS
EOF
  fi

  chmod 0644 "$tmp"
  run_as_user install -m 0644 "$tmp" "$path"
  rm -f "$tmp"
  record_change "Configured Polaris Headless Stream defaults in $path."
}

install_and_configure_polaris() {
  [[ "$ENABLE_POLARIS" == "1" ]] || return 0

  local package_file
  package_file="$(mktemp --suffix=.pkg.tar.zst)"
  log "Downloading Polaris Arch package from $POLARIS_PACKAGE_URL."
  download_file "$POLARIS_PACKAGE_URL" "$package_file"

  local pacman_args=(-U --needed)
  if [[ "$ASSUME_YES" == "1" ]]; then
    pacman_args+=(--noconfirm)
  fi
  run_sudo pacman "${pacman_args[@]}" "$package_file"
  rm -f "$package_file"
  record_change "Installed or verified Polaris from the upstream Arch package."

  run_sudo polaris --setup-host
  record_change "Ran Polaris host setup helper."

  upsert_polaris_config

  if [[ "$ENABLE_POLARIS_USER_SERVICE" == "1" ]]; then
    if run_as_user systemctl --user enable --now polaris; then
      record_change "Enabled and started Polaris user service for $TARGET_USER."
    else
      warn "Could not enable/start the Polaris user service for $TARGET_USER. After logging in as $TARGET_USER, run: systemctl --user enable --now polaris"
    fi
  fi
}

clone_or_update_config_repo() {
  run_as_user mkdir -p "$(dirname "$CONFIG_REPO_DIR")"

  if [[ -d "$CONFIG_REPO_DIR/.git" ]]; then
    local current_url
    current_url="$(run_as_user git -C "$CONFIG_REPO_DIR" config --get remote.origin.url || true)"
    if [[ "$current_url" != "$CONFIG_REPO_URL" ]]; then
      warn "$CONFIG_REPO_DIR is a git repository with origin $current_url, not $CONFIG_REPO_URL. Backing it up and cloning fresh."
      backup_user_path "$CONFIG_REPO_DIR"
      safe_rm_rf "$CONFIG_REPO_DIR"
      run_as_user git clone "$CONFIG_REPO_URL" "$CONFIG_REPO_DIR"
    else
      log "Updating config repository at $CONFIG_REPO_DIR."
      run_as_user git -C "$CONFIG_REPO_DIR" fetch --prune
      run_as_user git -C "$CONFIG_REPO_DIR" pull --ff-only
    fi
  elif [[ -e "$CONFIG_REPO_DIR" ]]; then
    warn "$CONFIG_REPO_DIR exists but is not a git repository. Backing it up and cloning fresh."
    backup_user_path "$CONFIG_REPO_DIR"
    safe_rm_rf "$CONFIG_REPO_DIR"
    run_as_user git clone "$CONFIG_REPO_URL" "$CONFIG_REPO_DIR"
  else
    log "Cloning config repository to $CONFIG_REPO_DIR."
    run_as_user git clone "$CONFIG_REPO_URL" "$CONFIG_REPO_DIR"
  fi

  record_change "Cloned or updated config repository $CONFIG_REPO_URL."
}

first_existing_path() {
  local candidate
  for candidate in "$@"; do
    if [[ -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

install_user_configs() {
  local src

  if src="$(first_existing_path \
    "$CONFIG_REPO_DIR/.config/alacritty" \
    "$CONFIG_REPO_DIR/config/alacritty" \
    "$CONFIG_REPO_DIR/alacritty")"; then
    replace_user_path_with_dir "$src" "$TARGET_HOME/.config/alacritty"
  elif src="$(first_existing_path \
    "$CONFIG_REPO_DIR/alacritty.toml" \
    "$CONFIG_REPO_DIR/.alacritty.toml")"; then
    replace_user_file "$src" "$TARGET_HOME/.config/alacritty/alacritty.toml"
  else
    warn "No Alacritty config found in $CONFIG_REPO_DIR."
  fi

  if src="$(first_existing_path \
    "$CONFIG_REPO_DIR/.config/niri" \
    "$CONFIG_REPO_DIR/config/niri" \
    "$CONFIG_REPO_DIR/niri")"; then
    replace_user_path_with_dir "$src" "$TARGET_HOME/.config/niri"
  else
    warn "No Niri config directory found in $CONFIG_REPO_DIR."
  fi

  if src="$(first_existing_path \
    "$CONFIG_REPO_DIR/noctalia" \
    "$CONFIG_REPO_DIR/noctalia-config" \
    "$CONFIG_REPO_DIR/.config/noctalia" \
    "$CONFIG_REPO_DIR/config/noctalia")"; then
    if [[ -d "$src" ]]; then
      replace_user_path_with_dir "$src" "$TARGET_HOME/$NOCTALIA_CONFIG_RELATIVE_DIR"
    else
      replace_user_file "$src" "$TARGET_HOME/$NOCTALIA_CONFIG_RELATIVE_DIR/$NOCTALIA_CONFIG_FILE"
    fi
  else
    warn "No Noctalia config found in $CONFIG_REPO_DIR."
  fi
}

localized_pictures_dir() {
  if [[ -n "$WALLPAPER_PARENT_DIR" ]]; then
    printf '%s\n' "$WALLPAPER_PARENT_DIR"
    return 0
  fi

  case "$SWEDISH_LOCALE" in
    sv_SE*|sv_*)
      printf '%s\n' "$TARGET_HOME/Bilder"
      ;;
    *)
      printf '%s\n' "$TARGET_HOME/Pictures"
      ;;
  esac
}

configure_xdg_user_dirs() {
  local pictures_dir
  pictures_dir="$(localized_pictures_dir)"
  local xdg_pictures_value="$pictures_dir"
  if [[ "$pictures_dir" == "$TARGET_HOME/"* ]]; then
    xdg_pictures_value="\$HOME/${pictures_dir#"$TARGET_HOME/"}"
  fi
  run_as_user mkdir -p "$pictures_dir"

  if have_command xdg-user-dirs-update; then
    run_as_user env LANG="$SWEDISH_LOCALE" xdg-user-dirs-update || warn "xdg-user-dirs-update failed for $TARGET_USER; you can re-run the script after checking xdg-user-dirs."
    run_as_user xdg-user-dirs-update --set PICTURES "$pictures_dir" || warn "Could not set XDG_PICTURES_DIR to $pictures_dir."
  else
    warn "xdg-user-dirs-update is not available; writing user-dirs.dirs directly."
  fi

  run_as_user mkdir -p "$TARGET_HOME/.config"
  if [[ -f "$TARGET_HOME/.config/user-dirs.dirs" ]]; then
    backup_user_path "$TARGET_HOME/.config/user-dirs.dirs"
    local tmp
    tmp="$(mktemp)"
    awk -v xdg_pictures_value="$xdg_pictures_value" '
      BEGIN { found = 0 }
      /^XDG_PICTURES_DIR=/ {
        print "XDG_PICTURES_DIR=\"" xdg_pictures_value "\""
        found = 1
        next
      }
      { print }
      END {
        if (!found) {
          print "XDG_PICTURES_DIR=\"" xdg_pictures_value "\""
        }
      }
    ' "$TARGET_HOME/.config/user-dirs.dirs" >"$tmp"
    chmod 0644 "$tmp"
    run_as_user install -m 0644 "$tmp" "$TARGET_HOME/.config/user-dirs.dirs"
    rm -f "$tmp"
  else
    write_user_file "$TARGET_HOME/.config/user-dirs.dirs" 0644 <<EOF
XDG_PICTURES_DIR="$xdg_pictures_value"
EOF
  fi

  record_change "Configured XDG pictures directory as $pictures_dir."
}

install_wallpapers() {
  local src
  if src="$(first_existing_path \
    "$CONFIG_REPO_DIR/wallpapers" \
    "$CONFIG_REPO_DIR/Pictures/wallpapers" \
    "$CONFIG_REPO_DIR/pictures/wallpapers")"; then
    local pictures_dir
    pictures_dir="$(localized_pictures_dir)"
    run_as_user mkdir -p "$pictures_dir"
    replace_user_path_with_dir "$src" "$pictures_dir/$WALLPAPER_SUBDIR"
  else
    warn "No wallpapers directory found in $CONFIG_REPO_DIR."
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

configure_noctalia_settings() {
  local wallpaper_dir
  local wallpaper_path
  local config_file="$TARGET_HOME/$NOCTALIA_CONFIG_RELATIVE_DIR/$NOCTALIA_CONFIG_FILE"
  local marker_begin="# BEGIN arch-niri-setup generated wallpaper settings"
  local marker_end="# END arch-niri-setup generated wallpaper settings"
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
  done < <(detect_connected_outputs)

  printf '%s\n' "$marker_end" >>"$tmp"

  if [[ "$found_output" == "0" ]]; then
    warn "No connected monitor names were found under /sys/class/drm; Noctalia wallpaper config will use default and last only."
  fi

  chmod 0644 "$tmp"
  run_as_user install -m 0644 "$tmp" "$config_file"
  rm -f "$tmp"

  if have_command noctalia; then
    run_as_user noctalia config validate "$config_file" || warn "Noctalia config validation failed for $config_file."
  fi

  record_change "Configured Noctalia wallpaper settings in $config_file."
}

set_gsettings_value() {
  local schema="$1"
  local key="$2"
  local value="$3"

  if ! run_as_user gsettings writable "$schema" "$key" >/dev/null 2>&1; then
    return 1
  fi

  if run_as_user gsettings set "$schema" "$key" "$value" >/dev/null 2>&1; then
    return 0
  fi

  if have_command dbus-run-session; then
    run_as_user dbus-run-session -- gsettings set "$schema" "$key" "$value" >/dev/null 2>&1
    return $?
  fi

  return 1
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
      -v prefer_dark="$GTK_APPLICATION_PREFER_DARK" '
      function emit_missing() {
        if (!seen_theme) {
          print "gtk-theme-name=" gtk_theme
        }
        if (!seen_dark) {
          print "gtk-application-prefer-dark-theme=" prefer_dark
        }
      }
      BEGIN {
        in_settings = 0
        saw_settings = 0
        seen_theme = 0
        seen_dark = 0
      }
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
      { print }
      END {
        if (in_settings) {
          emit_missing()
        } else if (!saw_settings) {
          print ""
          print "[Settings]"
          print "gtk-theme-name=" gtk_theme
          print "gtk-application-prefer-dark-theme=" prefer_dark
        }
      }
    ' "$path" >"$tmp"
  else
    cat >"$tmp" <<EOF
[Settings]
gtk-theme-name=$GTK_THEME_NAME
gtk-application-prefer-dark-theme=$GTK_APPLICATION_PREFER_DARK
EOF
  fi

  chmod 0644 "$tmp"
  run_as_user install -m 0644 "$tmp" "$path"
  rm -f "$tmp"
}

configure_gtk_dark_mode() {
  upsert_gtk_settings_file "$TARGET_HOME/.config/gtk-3.0/settings.ini"
  upsert_gtk_settings_file "$TARGET_HOME/.config/gtk-4.0/settings.ini"

  if set_gsettings_value org.gnome.desktop.interface color-scheme "$GTK_COLOR_SCHEME"; then
    record_change "Set GNOME color-scheme to $GTK_COLOR_SCHEME."
  else
    warn "Could not set org.gnome.desktop.interface color-scheme with gsettings; GTK settings.ini files were still written."
  fi

  if ! set_gsettings_value org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME"; then
    warn "Could not set org.gnome.desktop.interface gtk-theme with gsettings; GTK settings.ini files were still written."
  fi

  record_change "Configured GTK dark mode preferences."
}

configure_user_environment() {
  run_as_user mkdir -p "$TARGET_HOME/.config/environment.d" "$TARGET_HOME/.icons/default"

  write_user_file "$TARGET_HOME/.config/environment.d/10-arch-niri-setup.conf" 0644 <<EOF
XDG_CURRENT_DESKTOP=niri
XDG_SESSION_DESKTOP=niri
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland;xcb
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
XKB_DEFAULT_LAYOUT=$XKB_LAYOUT
XCURSOR_THEME=$CURSOR_THEME
XCURSOR_SIZE=$CURSOR_SIZE
EOF

  write_user_file "$TARGET_HOME/.icons/default/index.theme" 0644 <<EOF
[Icon Theme]
Inherits=$CURSOR_THEME
EOF

  ensure_niri_keyboard_config
  configure_xdg_user_dirs
  configure_gtk_dark_mode
  record_change "Configured user environment, cursor defaults, and XDG user directories."
}

ensure_niri_keyboard_config() {
  local config_dir="$TARGET_HOME/.config/niri"
  local config_file="$config_dir/config.kdl"
  run_as_user mkdir -p "$config_dir"

  if [[ ! -f "$config_file" ]]; then
    write_user_file "$config_file" 0644 <<EOF
input {
    keyboard {
        xkb {
            layout "$XKB_LAYOUT"
        }
    }
}
EOF
    record_change "Created a minimal Niri config with Swedish keyboard layout."
    return 0
  fi

  if grep -Eq 'layout[[:space:]]+"?'"$XKB_LAYOUT"'"?' "$config_file"; then
    log "Niri config already appears to include keyboard layout $XKB_LAYOUT."
    return 0
  fi

  if grep -Eq '^[[:space:]]*input([[:space:]]|\{|$)' "$config_file"; then
    warn "$config_file already has an input block. I did not edit it automatically; ensure it sets xkb layout \"$XKB_LAYOUT\"."
    return 0
  fi

  backup_user_path "$config_file"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<EOF

input {
    keyboard {
        xkb {
            layout "$XKB_LAYOUT"
        }
    }
}
EOF
  run_as_user tee -a "$config_file" <"$tmp" >/dev/null
  rm -f "$tmp"
  record_change "Added Swedish keyboard layout block to $config_file."
}

toml_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

configure_noctalia_greeter_runtime() {
  if [[ -x /usr/share/noctalia-greeter/setup_greeter_system.sh ]]; then
    run_sudo env \
      GREETER_USER="$GREETD_USER" \
      NOCTALIA_GREETER_SESSION_BIN="$NOCTALIA_GREETER_SESSION_BIN" \
      /usr/share/noctalia-greeter/setup_greeter_system.sh
    record_change "Ran Noctalia Greeter system setup helper."
  else
    warn "Noctalia Greeter setup helper was not found at /usr/share/noctalia-greeter/setup_greeter_system.sh. If greetd fails, reinstall $AUR_PACKAGE_NOCTALIA_GREETER and re-run."
  fi
}

configure_greetd() {
  [[ "$ENABLE_GREETD" == "1" ]] || return 0

  if ! id "$GREETD_USER" >/dev/null 2>&1; then
    if ! ask_yes_no "greetd user '$GREETD_USER' does not exist. Create it now?" y; then
      die "greetd cannot be configured with missing user '$GREETD_USER'. Set GREETD_USER to an existing user or allow the script to create it."
    fi
    run_sudo useradd -r -d /var/lib/noctalia-greeter -G video -s /usr/bin/nologin "$GREETD_USER"
    record_change "Created dedicated greetd user $GREETD_USER."
  fi

  local greeter_home
  greeter_home="$(getent passwd "$GREETD_USER" | cut -d: -f6)"
  if [[ "$greeter_home" != "/var/lib/noctalia-greeter" ]]; then
    if ask_yes_no "greetd user '$GREETD_USER' has home '$greeter_home'. Change it to /var/lib/noctalia-greeter for Noctalia Greeter?" y; then
      run_sudo usermod -d /var/lib/noctalia-greeter "$GREETD_USER"
      record_change "Changed $GREETD_USER home to /var/lib/noctalia-greeter."
    else
      warn "$GREETD_USER home was left as $greeter_home; Noctalia Greeter may not be able to store state or logs."
    fi
  fi

  if [[ ! -x "$NOCTALIA_GREETER_SESSION_BIN" ]]; then
    warn "Noctalia Greeter session wrapper $NOCTALIA_GREETER_SESSION_BIN is not executable. Reinstall $AUR_PACKAGE_NOCTALIA_GREETER or override NOCTALIA_GREETER_SESSION_BIN."
  fi

  configure_noctalia_greeter_runtime

  local escaped_command
  escaped_command="$(toml_escape "$NOCTALIA_GREETER_COMMAND")"
  local escaped_user
  escaped_user="$(toml_escape "$GREETD_USER")"
  write_system_file /etc/greetd/config.toml 0644 <<EOF
[terminal]
vt = 1

[default_session]
command = "$escaped_command"
user = "$escaped_user"
EOF

  local conflicting_services=()
  if [[ "$DISABLE_CONFLICTING_DISPLAY_MANAGERS" == "1" ]]; then
    local service
    for service in gdm.service sddm.service lightdm.service lxdm.service ly.service emptty.service; do
      if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        if ask_yes_no "Display manager $service is enabled and may conflict with greetd. Disable it?" y; then
          log "Disabling conflicting display manager $service."
          run_sudo systemctl disable "$service"
          record_change "Disabled conflicting display manager $service."
        else
          conflicting_services+=("$service")
          warn "$service was left enabled at your request."
        fi
      fi
    done
  fi

  if ((${#conflicting_services[@]})); then
    if ! ask_yes_no "Enable greetd.service anyway while another display manager remains enabled?" n; then
      warn "greetd.service was not enabled because conflicting display managers remain enabled: ${conflicting_services[*]}"
      return 0
    fi
  fi

  run_sudo systemctl enable greetd.service
  record_change "Configured greetd to launch Noctalia Greeter and enabled greetd.service."
}

configure_nautilus_terminal() {
  local schema="com.github.stunkymonkey.nautilus-open-any-terminal"
  if run_as_user gsettings list-schemas | grep -Fxq "$schema"; then
    run_as_user gsettings set "$schema" terminal alacritty || warn "Could not set Nautilus terminal integration with gsettings."
    record_change "Configured nautilus-open-any-terminal to use Alacritty."
  else
    warn "gsettings schema $schema was not available. Log out/in after package installation, then re-run if Nautilus still does not use Alacritty."
  fi
}

configure_locale_and_keyboard() {
  backup_system_path /etc/locale.gen
  local tmp
  tmp="$(mktemp)"
  awk -v locale="$SWEDISH_LOCALE UTF-8" '
    BEGIN { found = 0 }
    $0 ~ "^[[:space:]]*#?[[:space:]]*" locale "[[:space:]]*$" {
      print locale;
      found = 1;
      next;
    }
    { print }
    END {
      if (!found) {
        print locale;
      }
    }
  ' /etc/locale.gen >"$tmp"
  run_sudo install -m 0644 "$tmp" /etc/locale.gen
  rm -f "$tmp"

  write_system_file /etc/locale.conf 0644 <<EOF
LANG=$SWEDISH_LOCALE
LC_COLLATE=C
EOF

  backup_system_path /etc/vconsole.conf
  write_system_file /etc/vconsole.conf 0644 <<EOF
KEYMAP=$CONSOLE_KEYMAP
EOF

  run_sudo locale-gen

  if have_command localectl; then
    backup_system_path /etc/X11/xorg.conf.d/00-keyboard.conf
    run_sudo localectl set-keymap "$CONSOLE_KEYMAP"
    run_sudo localectl set-x11-keymap "$XKB_LAYOUT" pc105
  fi

  record_change "Configured Swedish locale and keyboard defaults."
}

configure_local_name_resolution() {
  local hosts_line="hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns"
  local tmp

  tmp="$(mktemp)"
  if [[ -f /etc/nsswitch.conf ]]; then
    awk -v hosts_line="$hosts_line" '
      BEGIN { found = 0 }
      /^[[:space:]]*hosts:[[:space:]]*/ {
        print hosts_line;
        found = 1;
        next;
      }
      { print }
      END {
        if (!found) {
          print hosts_line;
        }
      }
    ' /etc/nsswitch.conf >"$tmp"
  else
    printf '%s\n' "$hosts_line" >"$tmp"
  fi

  backup_system_path /etc/nsswitch.conf
  run_sudo install -m 0644 "$tmp" /etc/nsswitch.conf
  rm -f "$tmp"
  record_change "Configured /etc/nsswitch.conf for .local mDNS name resolution."

  if run_sudo systemctl enable --now avahi-daemon.service; then
    record_change "Enabled avahi-daemon.service for .local mDNS discovery."
  else
    warn "Could not enable and start avahi-daemon.service; .local resolution may not work until Avahi is running."
  fi
}

configure_fish_shell() {
  local fish_path
  fish_path="$(command -v fish || true)"
  [[ -n "$fish_path" ]] || die "Fish was installed but was not found in PATH."

  append_line_if_missing_system /etc/shells "$fish_path"

  local current_shell
  current_shell="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
  if [[ "$current_shell" != "$fish_path" ]]; then
    run_sudo chsh -s "$fish_path" "$TARGET_USER"
    record_change "Changed $TARGET_USER's login shell to Fish."
  else
    log "$TARGET_USER already uses Fish as the login shell."
  fi
}

snapper_has_config() {
  [[ -d /etc/snapper/configs ]] || return 1
  find /etc/snapper/configs -mindepth 1 -maxdepth 1 -type f -print -quit | grep -q .
}

configure_snapshots() {
  [[ "$ENABLE_SNAPSHOTS" == "1" ]] || return 0

  if ! snapper_has_config; then
    warn "Snapper does not appear to have configs under /etc/snapper/configs. Not installing snap-pac hooks; create/repair Snapper config first, then re-run."
    return 0
  fi

  local pacman_args=(-S --needed)
  if [[ "$ASSUME_YES" == "1" ]]; then
    pacman_args+=(--noconfirm)
  fi
  run_sudo pacman "${pacman_args[@]}" snap-pac
  run_sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer || warn "Could not enable Snapper timers. snap-pac hooks may still work for pacman transactions."
  record_change "Installed snap-pac and enabled Snapper maintenance timers where available."
}

mkinitcpio_has_hook() {
  local hook="$1"
  awk -v hook="$hook" '
    /^[[:space:]]*HOOKS[[:space:]]*=/ {
      line = $0
      sub(/^[[:space:]]*HOOKS[[:space:]]*=[[:space:]]*\(/, "", line)
      sub(/\)[[:space:]]*$/, "", line)
      count = split(line, hooks, /[[:space:]]+/)
      for (i = 1; i <= count; i++) {
        if (hooks[i] == hook) {
          found = 1
        }
      }
    }
    END { exit found ? 0 : 1 }
  ' /etc/mkinitcpio.conf
}

detect_plymouth_hook() {
  if mkinitcpio_has_hook systemd; then
    printf 'sd-plymouth'
  else
    printf 'plymouth'
  fi
}

ensure_mkinitcpio_plymouth_hook() {
  local hook="$1"
  if mkinitcpio_has_hook "$hook"; then
    log "mkinitcpio already includes $hook."
    return 0
  fi

  backup_system_path /etc/mkinitcpio.conf
  local tmp
  tmp="$(mktemp)"
  awk -v hook="$hook" '
    function insert_hook(body, out, hooks, count, i, inserted) {
      count = split(body, hooks, /[[:space:]]+/)
      out = ""
      inserted = 0
      for (i = 1; i <= count; i++) {
        if (hooks[i] == "") {
          continue
        }
        out = out (out ? " " : "") hooks[i]
        if (!inserted && (hooks[i] == "udev" || hooks[i] == "systemd")) {
          out = out " " hook
          inserted = 1
        }
      }
      if (!inserted) {
        out = out (out ? " " : "") hook
      }
      return out
    }
    /^[[:space:]]*HOOKS[[:space:]]*=\(/ {
      line = $0
      sub(/^[[:space:]]*HOOKS[[:space:]]*=\(/, "", line)
      sub(/\)[[:space:]]*$/, "", line)
      print "HOOKS=(" insert_hook(line) ")"
      next
    }
    { print }
  ' /etc/mkinitcpio.conf >"$tmp"
  run_sudo install -m 0644 "$tmp" /etc/mkinitcpio.conf
  rm -f "$tmp"
  record_change "Added $hook to mkinitcpio HOOKS."
}

configure_limine_for_plymouth() {
  [[ -f "$LIMINE_CONFIG" ]] || {
    warn "Limine config $LIMINE_CONFIG was not found. Plymouth was configured, but kernel arguments were not changed."
    return 0
  }

  local selected_entry=""
  local selected_default="$LIMINE_DEFAULT_ENTRY"
  local update_all_cmdlines=0
  local limine_matches=()
  mapfile -t limine_matches < <(awk \
    -v entry_pattern="$LIMINE_ARCH_ENTRY_MATCH" \
    -v selected_default="$selected_default" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function is_entry(line) {
      return line ~ /^[[:space:]]*[:\/][^\/]/
    }
    function entry_name(line, value) {
      value = line
      sub(/^[[:space:]]*[:\/][[:space:]]*/, "", value)
      return trim(value)
    }
    is_entry($0) {
      name = entry_name($0)
      if ((selected_default != "" && name == selected_default) || (selected_default == "" && name ~ entry_pattern)) {
        print name
      }
    }
  ' "$LIMINE_CONFIG")

  if ((${#limine_matches[@]} == 0)); then
    if [[ -n "$selected_default" ]]; then
      warn "LIMINE_DEFAULT_ENTRY '$selected_default' was not found in $LIMINE_CONFIG. Kernel arguments were not changed."
      return 0
    fi

    local limine_cmdline_count
    limine_cmdline_count="$(awk '
      /^[[:space:]]*(cmdline|kernel_cmdline)[[:space:]]*:/ || /^[[:space:]]*(CMDLINE|KERNEL_CMDLINE)[[:space:]]*=/ {
        count++
      }
      END { print count + 0 }
    ' "$LIMINE_CONFIG")"

    if [[ "$limine_cmdline_count" -eq 0 ]]; then
      warn "No matching Limine entries and no cmdline/CMDLINE lines were found in $LIMINE_CONFIG. Kernel arguments were not changed."
      return 0
    fi

    if [[ "$ASSUME_YES" == "1" ]]; then
      warn "No Limine entries matched and ASSUME_YES=1 cannot safely choose whether to update all cmdline lines. Kernel arguments were not changed."
      return 0
    fi

    if ask_yes_no "No Limine entries matched. Update all $limine_cmdline_count cmdline/CMDLINE line(s) with Plymouth args?" n; then
      update_all_cmdlines=1
      selected_default=""
    else
      warn "No Limine entries matched and all-cmdline update was declined. Kernel arguments were not changed."
      return 0
    fi
  fi

  if [[ -n "$selected_default" ]]; then
    selected_entry="$selected_default"
  elif ((${#limine_matches[@]} > 1)); then
    if [[ "$ASSUME_YES" == "1" ]]; then
      warn "Multiple Limine entries matched and ASSUME_YES=1 cannot choose one safely. Set LIMINE_DEFAULT_ENTRY and re-run to update Limine."
      return 0
    fi
    require_tty_for_prompt
    printf 'Multiple Limine entries matched %s:\n' "$LIMINE_ARCH_ENTRY_MATCH" >/dev/tty
    printf ' - %s\n' "${limine_matches[@]}" >/dev/tty
    selected_entry="$(ask_value "Enter the exact Limine entry to configure, or leave blank to skip" "")"
    if [[ -z "$selected_entry" ]]; then
      warn "Multiple Limine entries matched and no entry was selected. Kernel arguments were not changed."
      return 0
    fi
    selected_default="$selected_entry"
  elif ((${#limine_matches[@]} == 1)) && [[ -z "$selected_default" ]]; then
    selected_entry="${limine_matches[0]}"
    selected_default="$selected_entry"
  fi

  backup_system_path "$LIMINE_CONFIG"

  local tmp
  tmp="$(mktemp)"
  local status_file
  status_file="$(mktemp)"

  awk \
    -v entry_pattern="$LIMINE_ARCH_ENTRY_MATCH" \
    -v selected_entry="$selected_entry" \
    -v configured_default="$selected_default" \
    -v update_all_cmdlines="$update_all_cmdlines" \
    -v quiet_enabled="$ENABLE_QUIET_KERNEL_ARG" \
    -v status_file="$status_file" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function has_arg(cmdline, arg) {
      return index(" " cmdline " ", " " arg " ") > 0
    }
    function add_arg(cmdline, arg) {
      if (has_arg(cmdline, arg)) {
        return cmdline
      }
      return trim(cmdline " " arg)
    }
    function is_entry(line) {
      return line ~ /^[[:space:]]*[:\/][^\/]/
    }
    function entry_name(line, value) {
      value = line
      sub(/^[[:space:]]*[:\/][[:space:]]*/, "", value)
      return trim(value)
    }
    function entry_matches(value) {
      if (update_all_cmdlines == "1") {
        return 1
      }
      if (selected_entry != "") {
        return value == selected_entry
      }
      return value ~ entry_pattern
    }
    BEGIN {
      entry = ""
      wanted_default = configured_default
      wrote_default = 0
      touched_cmdline = 0
    }
    {
      line = $0
      if (is_entry(line)) {
        entry = entry_name(line)
        if (entry_matches(entry)) {
          if (wanted_default == "") {
            wanted_default = entry
          }
        }
      }

      if ((line ~ /^[[:space:]]*(cmdline|kernel_cmdline)[[:space:]]*:/ || line ~ /^[[:space:]]*(CMDLINE|KERNEL_CMDLINE)[[:space:]]*=/) && entry_matches(entry)) {
        prefix = line
        if (line ~ /:/) {
          sub(/:.*/, ": ", prefix)
          cmd = line
          sub(/^[^:]*:[[:space:]]*/, "", cmd)
        } else {
          sub(/=.*/, "=", prefix)
          cmd = line
          sub(/^[^=]*=[[:space:]]*/, "", cmd)
        }
        cmd = add_arg(cmd, "splash")
        if (quiet_enabled == "1") {
          cmd = add_arg(cmd, "quiet")
        }
        print prefix cmd
        touched_cmdline = 1
        next
      }

      if (line ~ /^[[:space:]]*default_entry[[:space:]]*:/ || line ~ /^[[:space:]]*DEFAULT_ENTRY[[:space:]]*=/) {
        if (wanted_default != "") {
          if (line ~ /:/) {
            print "default_entry: " wanted_default
          } else {
            print "DEFAULT_ENTRY=" wanted_default
          }
          wrote_default = 1
          next
        }
      }

      print line
    }
    END {
      if (update_all_cmdlines != "1" && wanted_default != "" && !wrote_default) {
        print ""
        print "default_entry: " wanted_default
      }
      print "touched_cmdline=" touched_cmdline > status_file
      print "wanted_default=" wanted_default >> status_file
    }
  ' "$LIMINE_CONFIG" >"$tmp"

  local touched_cmdline
  local wanted_default
  touched_cmdline="$(awk -F= '$1 == "touched_cmdline" { print $2 }' "$status_file")"
  wanted_default="$(sed -n 's/^wanted_default=//p' "$status_file")"
  rm -f "$status_file"

  if [[ "${touched_cmdline:-0}" -eq 0 ]]; then
    rm -f "$tmp"
    warn "No editable cmdline/CMDLINE line was found in the selected Limine scope. Add splash manually or adjust LIMINE_ARCH_ENTRY_MATCH."
    return 0
  fi

  run_sudo install -m 0644 "$tmp" "$LIMINE_CONFIG"
  rm -f "$tmp"
  if [[ "$update_all_cmdlines" == "1" ]]; then
    record_change "Updated all cmdline/CMDLINE lines in $LIMINE_CONFIG for Plymouth kernel arguments."
  else
    record_change "Updated Limine config $LIMINE_CONFIG for Plymouth kernel arguments and default entry ${wanted_default:-unset}."
  fi
}

configure_plymouth() {
  [[ "$ENABLE_PLYMOUTH" == "1" ]] || return 0

  local hook
  hook="$(detect_plymouth_hook)"
  ensure_mkinitcpio_plymouth_hook "$hook"
  run_sudo plymouth-set-default-theme "$PLYMOUTH_THEME"
  configure_limine_for_plymouth
  run_sudo mkinitcpio -P
  record_change "Configured Plymouth theme $PLYMOUTH_THEME and rebuilt initramfs."
}

configure_cursor_theme_system() {
  write_system_file /usr/share/icons/default/index.theme 0644 <<EOF
[Icon Theme]
Inherits=$CURSOR_THEME
EOF
  record_change "Configured system cursor theme to $CURSOR_THEME."
}

print_summary() {
  local item

  printf '\n%sSetup summary%s\n' "$C_BOLD" "$C_RESET"
  printf '%s=============%s\n' "$C_DIM" "$C_RESET"
  printf 'Log file: %s\n' "$LOG_FILE"
  printf 'User backups: %s\n' "$USER_BACKUP_ROOT"
  printf 'System backups: %s\n' "$SYSTEM_BACKUP_ROOT"

  if ((${#CHANGES[@]})); then
    printf '\n%sChanges made or verified:%s\n' "$C_GREEN" "$C_RESET"
    for item in "${CHANGES[@]}"; do
      printf ' %s-%s %s\n' "$C_GREEN" "$C_RESET" "$item"
    done
  fi

  if ((${#WARNINGS[@]})); then
    printf '\n%sWarnings:%s\n' "$C_YELLOW" "$C_RESET"
    for item in "${WARNINGS[@]}"; do
      printf ' %s-%s %s\n' "$C_YELLOW" "$C_RESET" "$item"
    done
  fi

  printf '\n%sYou can safely re-run this script after addressing any warnings or package-name changes.%s\n' "$C_CYAN" "$C_RESET"
}

main() {
  require_normal_user
  configure_guided_install
  resolve_target_user
  prepare_runtime
  enable_multilib
  install_official_packages
  install_paru_if_missing
  install_aur_packages
  install_and_configure_polaris
  clone_or_update_config_repo
  install_user_configs
  configure_user_environment
  install_wallpapers
  configure_noctalia_settings
  configure_greetd
  configure_nautilus_terminal
  configure_locale_and_keyboard
  configure_local_name_resolution
  configure_fish_shell
  configure_snapshots
  configure_cursor_theme_system
  configure_plymouth
  print_summary
}

main "$@"
