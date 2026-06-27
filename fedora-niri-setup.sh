#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_REPO_URL="${CONFIG_REPO_URL:-https://github.com/socawi-ai/linux-niri}"
CONFIG_REPO_DIR_WAS_SET=0
CONFIG_SOURCE_DIR_WAS_SET=0
USER_BACKUP_ROOT_WAS_SET=0
[[ -n "${CONFIG_REPO_DIR+x}" ]] && CONFIG_REPO_DIR_WAS_SET=1
[[ -n "${CONFIG_SOURCE_DIR+x}" ]] && CONFIG_SOURCE_DIR_WAS_SET=1
[[ -n "${USER_BACKUP_ROOT+x}" ]] && USER_BACKUP_ROOT_WAS_SET=1
CONFIG_REPO_BRANCH="${CONFIG_REPO_BRANCH:-main}"
CONFIG_REPO_DIR="${CONFIG_REPO_DIR:-$HOME/.cache/fedora-niri-setup/linux-niri}"
CONFIG_SOURCE_DIR="${CONFIG_SOURCE_DIR:-}"
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
ASSUME_YES="${ASSUME_YES:-0}"
EXTRA_FEDORA_PACKAGES="${EXTRA_FEDORA_PACKAGES:-}"

ENABLE_NOCTALIA_COPR="${ENABLE_NOCTALIA_COPR:-1}"
ENABLE_GREETD="${ENABLE_GREETD:-1}"
ENABLE_LIMINE="${ENABLE_LIMINE:-0}"
REMOVE_GRUB_AFTER_LIMINE="${REMOVE_GRUB_AFTER_LIMINE:-1}"
PURGE_GRUB_PACKAGES="${PURGE_GRUB_PACKAGES:-0}"
DISABLE_CONFLICTING_DISPLAY_MANAGERS="${DISABLE_CONFLICTING_DISPLAY_MANAGERS:-1}"
NOCTALIA_COPR="${NOCTALIA_COPR:-lionheartp/Hyprland}"
NOCTALIA_PACKAGE="${NOCTALIA_PACKAGE:-noctalia-git}"
NOCTALIA_GREETER_PACKAGE="${NOCTALIA_GREETER_PACKAGE:-noctalia-greeter}"
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
WALLPAPER_PARENT_DIR="${WALLPAPER_PARENT_DIR:-}"
WALLPAPER_SUBDIR="${WALLPAPER_SUBDIR:-wallpapers}"
LIMINE_BOOT_LABEL="${LIMINE_BOOT_LABEL:-Fedora Limine}"
LIMINE_TIMEOUT="${LIMINE_TIMEOUT:-5}"
LIMINE_BOOT_ROOT="${LIMINE_BOOT_ROOT:-/boot}"
LIMINE_CONFIG="${LIMINE_CONFIG:-$LIMINE_BOOT_ROOT/limine/limine.conf}"
LIMINE_EFI_DIR="${LIMINE_EFI_DIR:-$LIMINE_BOOT_ROOT/EFI/Limine}"
LIMINE_FALLBACK_EFI="${LIMINE_FALLBACK_EFI:-1}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_FILE:-$HOME/fedora-niri-setup-$TIMESTAMP.log}"
USER_BACKUP_ROOT="${USER_BACKUP_ROOT:-$HOME/.local/share/fedora-niri-setup/backups/$TIMESTAMP}"
SYSTEM_BACKUP_ROOT="${SYSTEM_BACKUP_ROOT:-/var/backups/fedora-niri-setup/$TIMESTAMP}"

TARGET_HOME="$HOME"
DNF_BIN=""

declare -a CHANGES=()
declare -a WARNINGS=()
declare -a USER_BACKUPS=()
declare -a SYSTEM_BACKUPS=()

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'die "Setup failed on or near line $LINENO. Review $LOG_FILE, fix the reported problem, then re-run the script."' ERR

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

warn() {
  WARNINGS+=("$*")
  printf '[%s] WARNING: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
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
    pipewire
    wireplumber
    pipewire-pulseaudio
    pipewire-alsa
    pipewire-jack-audio-connection-kit
  )

  # Bitwarden is in the Arch official list, but it is not consistently available
  # from Fedora's enabled official repositories. Keep it opt-in for now.
  if [[ "${INSTALL_BITWARDEN:-0}" == "1" ]]; then
    packages+=(bitwarden)
  fi

  if [[ -n "$EXTRA_FEDORA_PACKAGES" ]]; then
    local extra_packages=()
    read -r -a extra_packages <<<"$EXTRA_FEDORA_PACKAGES"
    packages+=("${extra_packages[@]}")
  fi

  log "Installing Fedora packages with $DNF_BIN."
  dnf_install "${packages[@]}"
  record_change "Installed or verified Fedora packages for a basic Niri desktop."
}

enable_noctalia_copr() {
  [[ "$ENABLE_NOCTALIA_COPR" == "1" ]] || {
    log "Noctalia COPR enablement is disabled."
    return 0
  }

  log "Ensuring COPR support is available."
  dnf_install dnf-plugins-core

  local repo_owner="${NOCTALIA_COPR%%/*}"
  local repo_name="${NOCTALIA_COPR#*/}"
  local repo_glob="/etc/yum.repos.d/*${repo_owner}*${repo_name}*.repo"
  if compgen -G "$repo_glob" >/dev/null; then
    log "COPR $NOCTALIA_COPR appears to be enabled."
  else
    log "Enabling COPR $NOCTALIA_COPR for Noctalia packages."
    run_sudo "$DNF_BIN" copr enable -y "$NOCTALIA_COPR"
    record_change "Enabled COPR $NOCTALIA_COPR."
  fi

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
      -v prefer_dark="$GTK_APPLICATION_PREFER_DARK" '
      function emit_missing() {
        if (!seen_theme) print "gtk-theme-name=" gtk_theme
        if (!seen_dark) print "gtk-application-prefer-dark-theme=" prefer_dark
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

  if run_as_user gsettings writable org.gnome.desktop.interface color-scheme >/dev/null 2>&1; then
    run_as_user gsettings set org.gnome.desktop.interface color-scheme "$GTK_COLOR_SCHEME" || warn "Could not set GNOME color-scheme."
  fi

  if run_as_user gsettings writable org.gnome.desktop.interface gtk-theme >/dev/null 2>&1; then
    run_as_user gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" || warn "Could not set GNOME gtk-theme."
  fi

  record_change "Configured basic GTK dark-mode preferences."
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

find_limine_efi_binary() {
  local candidate
  local candidates=(
    /usr/share/limine/BOOTX64.EFI
    /usr/share/limine/limine-x64.efi
    /usr/share/limine/limine-x86_64.efi
    /usr/lib/limine/BOOTX64.EFI
    /usr/lib/limine/limine-x64.efi
    /usr/lib64/limine/BOOTX64.EFI
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  candidate="$(find /usr/share/limine /usr/lib/limine /usr/lib64/limine -type f \( -iname 'BOOTX64.EFI' -o -iname 'limine*.efi' \) 2>/dev/null | head -n 1 || true)"
  [[ -n "$candidate" ]] || return 1
  printf '%s\n' "$candidate"
}

limine_boot_path() {
  local path="$1"
  if [[ "$path" == "$LIMINE_BOOT_ROOT/"* ]]; then
    path="${path#"$LIMINE_BOOT_ROOT"}"
  fi
  [[ "$path" == /* ]] || path="/$path"
  printf 'boot():%s\n' "$path"
}

install_limine_packages() {
  [[ "$ENABLE_LIMINE" == "1" ]] || return 0

  log "Installing Limine bootloader packages."
  dnf_install limine efibootmgr
  have_command efibootmgr || die "efibootmgr was installed but is not available in PATH."
  find_limine_efi_binary >/dev/null || die "Could not find a Limine EFI binary after installing the limine package."
  record_change "Installed or verified Limine and efibootmgr."
}

write_limine_config_from_bls() {
  [[ "$ENABLE_LIMINE" == "1" ]] || return 0

  local entries_dir="$LIMINE_BOOT_ROOT/loader/entries"
  [[ -d "$entries_dir" ]] || die "Fedora BLS entries were not found at $entries_dir."

  local entry_files=()
  mapfile -t entry_files < <(find "$entries_dir" -maxdepth 1 -type f -name '*.conf' -print | sort -Vr)
  ((${#entry_files[@]})) || die "No Fedora BLS entry files found in $entries_dir."

  local tmp
  tmp="$(mktemp)"
  {
    printf 'timeout: %s\n' "$LIMINE_TIMEOUT"
    printf '\n'
  } >"$tmp"

  local entry
  for entry in "${entry_files[@]}"; do
    local title
    local linux_path
    local initrd_line
    local options
    local initrd_path

    title="$(awk '/^[[:space:]]*title[[:space:]]+/ { sub(/^[[:space:]]*title[[:space:]]+/, ""); print; exit }' "$entry")"
    linux_path="$(awk '/^[[:space:]]*linux[[:space:]]+/ { sub(/^[[:space:]]*linux[[:space:]]+/, ""); print; exit }' "$entry")"
    initrd_line="$(awk '/^[[:space:]]*initrd[[:space:]]+/ { sub(/^[[:space:]]*initrd[[:space:]]+/, ""); print; exit }' "$entry")"
    options="$(awk '/^[[:space:]]*options[[:space:]]+/ { sub(/^[[:space:]]*options[[:space:]]+/, ""); print; exit }' "$entry")"

    [[ -n "$linux_path" ]] || {
      warn "Skipping BLS entry without linux path: $entry"
      continue
    }

    title="${title:-$(basename "$entry" .conf)}"
    {
      printf '/%s\n' "$title"
      printf '    protocol: linux\n'
      printf '    kernel_path: %s\n' "$(limine_boot_path "$linux_path")"
      for initrd_path in $initrd_line; do
        [[ -n "$initrd_path" ]] || continue
        printf '    module_path: %s\n' "$(limine_boot_path "$initrd_path")"
      done
      printf '    cmdline: %s\n' "$options"
      printf '\n'
    } >>"$tmp"
  done

  if ! grep -Eq '^/' "$tmp"; then
    rm -f "$tmp"
    die "Could not generate any Limine entries from $entries_dir."
  fi

  write_system_file "$LIMINE_CONFIG" 0644 <"$tmp"
  rm -f "$tmp"
  record_change "Generated Limine config from Fedora BLS entries at $LIMINE_CONFIG."
}

install_limine_efi_files() {
  [[ "$ENABLE_LIMINE" == "1" ]] || return 0

  local limine_efi
  limine_efi="$(find_limine_efi_binary)"

  run_sudo install -d -m 0755 "$LIMINE_EFI_DIR"
  backup_system_path "$LIMINE_EFI_DIR/limine.efi"
  run_sudo install -m 0644 "$limine_efi" "$LIMINE_EFI_DIR/limine.efi"

  if [[ "$LIMINE_FALLBACK_EFI" == "1" ]]; then
    run_sudo install -d -m 0755 "$LIMINE_BOOT_ROOT/EFI/BOOT"
    backup_system_path "$LIMINE_BOOT_ROOT/EFI/BOOT/BOOTX64.EFI"
    run_sudo install -m 0644 "$limine_efi" "$LIMINE_BOOT_ROOT/EFI/BOOT/BOOTX64.EFI"
    record_change "Installed Limine EFI binary to $LIMINE_EFI_DIR/limine.efi and fallback BOOTX64.EFI."
  else
    record_change "Installed Limine EFI binary to $LIMINE_EFI_DIR/limine.efi."
  fi
}

create_limine_uefi_entry() {
  [[ "$ENABLE_LIMINE" == "1" ]] || return 0

  [[ -d /sys/firmware/efi ]] || {
    warn "This system does not appear to be booted in UEFI mode. Limine files were installed, but no UEFI boot entry was created."
    return 0
  }

  local boot_source
  local boot_disk_name
  local boot_partnum
  local boot_disk

  boot_source="$(findmnt -no SOURCE --target "$LIMINE_BOOT_ROOT" | head -n 1)"
  [[ "$boot_source" == /dev/* ]] || {
    warn "Could not determine a block device for $LIMINE_BOOT_ROOT; skipping efibootmgr entry creation."
    return 0
  }

  boot_disk_name="$(lsblk -no PKNAME "$boot_source" | head -n 1 | tr -d '[:space:]')"
  boot_partnum="$(lsblk -no PARTNUM "$boot_source" | head -n 1 | tr -d '[:space:]')"
  if [[ -z "$boot_disk_name" || -z "$boot_partnum" ]]; then
    warn "Could not derive parent disk and partition number from $boot_source; skipping efibootmgr entry creation."
    return 0
  fi

  boot_disk="/dev/$boot_disk_name"
  run_sudo efibootmgr -c -d "$boot_disk" -p "$boot_partnum" -L "$LIMINE_BOOT_LABEL" -l "\\EFI\\Limine\\limine.efi"
  record_change "Created UEFI boot entry '$LIMINE_BOOT_LABEL' for $boot_disk partition $boot_partnum."
}

disable_grub_efi_path() {
  [[ "$ENABLE_LIMINE" == "1" && "$REMOVE_GRUB_AFTER_LIMINE" == "1" ]] || return 0

  local grub_efi_dir="$LIMINE_BOOT_ROOT/EFI/fedora"
  if [[ -e "$grub_efi_dir" ]]; then
    local disabled_dir="$LIMINE_BOOT_ROOT/EFI/fedora.grub-disabled-$TIMESTAMP"
    backup_system_path "$grub_efi_dir"
    run_sudo mv "$grub_efi_dir" "$disabled_dir"
    record_change "Moved GRUB EFI directory out of the active path: $grub_efi_dir -> $disabled_dir."
  else
    log "No Fedora GRUB EFI directory found at $grub_efi_dir."
  fi

  if [[ "$PURGE_GRUB_PACKAGES" == "1" ]]; then
    warn "PURGE_GRUB_PACKAGES=1 is set; removing GRUB EFI/shim packages after Limine install."
    run_sudo "$DNF_BIN" remove -y 'grub2-efi*' 'shim*'
    record_change "Removed GRUB EFI and shim packages."
  fi
}

configure_limine_bootloader() {
  [[ "$ENABLE_LIMINE" == "1" ]] || return 0

  log "Configuring Limine as the Fedora bootloader using $LIMINE_BOOT_ROOT."
  install_limine_packages
  write_limine_config_from_bls
  install_limine_efi_files
  create_limine_uefi_entry
  disable_grub_efi_path
  warn "Limine was installed and GRUB was removed from the active EFI path. Reboot only when you are ready to test the new bootloader."
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
  require_fedora
  resolve_target_user
  prepare_runtime
  install_fedora_packages
  install_noctalia_packages
  clone_or_update_config_repo
  verify_config_source
  install_user_configs
  ensure_niri_autostarts_noctalia
  configure_user_environment
  install_wallpapers
  configure_noctalia_settings
  configure_gtk_dark_mode
  configure_noctalia_greeter
  configure_limine_bootloader
  print_summary
}

main "$@"
