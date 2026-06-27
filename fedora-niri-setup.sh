#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_SOURCE_DIR="${CONFIG_SOURCE_DIR:-}"
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
ASSUME_YES="${ASSUME_YES:-0}"
EXTRA_FEDORA_PACKAGES="${EXTRA_FEDORA_PACKAGES:-}"

ENABLE_NOCTALIA_COPR="${ENABLE_NOCTALIA_COPR:-1}"
ENABLE_GREETD="${ENABLE_GREETD:-1}"
DISABLE_CONFLICTING_DISPLAY_MANAGERS="${DISABLE_CONFLICTING_DISPLAY_MANAGERS:-1}"
NOCTALIA_COPR="${NOCTALIA_COPR:-lionheartp/Hyprland}"
NOCTALIA_PACKAGE="${NOCTALIA_PACKAGE:-noctalia-git}"
NOCTALIA_GREETER_PACKAGE="${NOCTALIA_GREETER_PACKAGE:-noctalia-greeter}"
GREETD_USER="${GREETD_USER:-greeter}"
NOCTALIA_GREETER_SESSION_BIN="${NOCTALIA_GREETER_SESSION_BIN:-}"

XKB_LAYOUT="${XKB_LAYOUT:-se}"
GTK_COLOR_SCHEME="${GTK_COLOR_SCHEME:-prefer-dark}"
GTK_THEME_NAME="${GTK_THEME_NAME:-Adwaita-dark}"
GTK_APPLICATION_PREFER_DARK="${GTK_APPLICATION_PREFER_DARK:-1}"

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

  if [[ -z "$CONFIG_SOURCE_DIR" ]]; then
    CONFIG_SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  fi

  log "Target user: $TARGET_USER"
  log "Target home: $TARGET_HOME"
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

install_user_configs() {
  if [[ -d "$CONFIG_SOURCE_DIR/alacritty" ]]; then
    replace_user_path_with_dir "$CONFIG_SOURCE_DIR/alacritty" "$TARGET_HOME/.config/alacritty"
  else
    warn "No Alacritty config found at $CONFIG_SOURCE_DIR/alacritty."
  fi

  if [[ -d "$CONFIG_SOURCE_DIR/niri" ]]; then
    replace_user_path_with_dir "$CONFIG_SOURCE_DIR/niri" "$TARGET_HOME/.config/niri"
  else
    warn "No Niri config found at $CONFIG_SOURCE_DIR/niri."
  fi

  if [[ -d "$CONFIG_SOURCE_DIR/noctalia" ]]; then
    replace_user_path_with_dir "$CONFIG_SOURCE_DIR/noctalia" "$TARGET_HOME/.config/noctalia"
  else
    warn "No Noctalia config found at $CONFIG_SOURCE_DIR/noctalia."
  fi
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
  install_user_configs
  ensure_niri_autostarts_noctalia
  configure_user_environment
  configure_gtk_dark_mode
  configure_noctalia_greeter
  print_summary
}

main "$@"
