#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_REPO_URL="${CONFIG_REPO_URL:-https://github.com/socawi-ai/linux-niri}"
CONFIG_REPO_DIR_WAS_SET=0
CONFIG_SOURCE_DIR_WAS_SET=0
USER_BACKUP_ROOT_WAS_SET=0
REFIND_THEME_DIR_WAS_SET=0
[[ -n "${CONFIG_REPO_DIR+x}" ]] && CONFIG_REPO_DIR_WAS_SET=1
[[ -n "${CONFIG_SOURCE_DIR+x}" ]] && CONFIG_SOURCE_DIR_WAS_SET=1
[[ -n "${USER_BACKUP_ROOT+x}" ]] && USER_BACKUP_ROOT_WAS_SET=1
[[ -n "${REFIND_THEME_DIR+x}" ]] && REFIND_THEME_DIR_WAS_SET=1
CONFIG_REPO_BRANCH="${CONFIG_REPO_BRANCH:-main}"
CONFIG_REPO_DIR="${CONFIG_REPO_DIR:-$HOME/.cache/arch-niri-setup/linux-niri}"
CONFIG_SOURCE_DIR="${CONFIG_SOURCE_DIR:-}"
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
ASSUME_YES="${ASSUME_YES:-1}"
EXTRA_ARCH_PACKAGES="${EXTRA_ARCH_PACKAGES:-}"

# AUR helper used for everything not in the official repos (Noctalia,
# Noctalia Greeter, nautilus-open-any-terminal, VS Code). Bootstrapped from
# scratch via git+makepkg if not already present. "paru" or "yay".
AUR_HELPER="${AUR_HELPER:-paru}"

ENABLE_GREETD="${ENABLE_GREETD:-1}"
ENABLE_MULTILIB="${ENABLE_MULTILIB:-1}"
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
# Steam/Proton games need the 32-bit (lib32) Mesa/Vulkan stack, not just the
# native 64-bit one — without it most games fail to launch at all. Vendor
# driver packages are picked automatically from `lspci` (see
# detect_gpu_vendors()); set to 0 if you'd rather manage graphics drivers
# yourself.
INSTALL_STEAM_GRAPHICS_DEPS="${INSTALL_STEAM_GRAPHICS_DEPS:-1}"
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
INSTALL_ARCH_UPDATE="${INSTALL_ARCH_UPDATE:-1}"
ENABLE_ARCH_UPDATE_TIMER="${ENABLE_ARCH_UPDATE_TIMER:-1}"
DISABLE_CONFLICTING_DISPLAY_MANAGERS="${DISABLE_CONFLICTING_DISPLAY_MANAGERS:-1}"

# rEFInd theme — this script assumes rEFInd is already installed and
# configured (e.g. via archinstall) and refuses to run (see require_refind())
# unless it can find refind.conf; it never installs rEFInd itself or touches
# its existing menu entries/scan config, only layers a visual theme on top.
# Set INSTALL_REFIND_THEME=0 to skip rEFInd entirely (no preflight check, no
# theming) if this machine doesn't use rEFInd at all.
INSTALL_REFIND_THEME="${INSTALL_REFIND_THEME:-1}"
REFIND_THEME_REPO="${REFIND_THEME_REPO:-https://github.com/NilsPvR/rEFInd-nils}"
REFIND_THEME_NAME="${REFIND_THEME_NAME:-rEFInd-nils}"
REFIND_THEME_DIR="${REFIND_THEME_DIR:-$HOME/.cache/arch-niri-setup/refind-theme}"
# Explicit override if find_refind_conf() can't locate refind.conf on its own
# (unusual ESP mount point or layout).
REFIND_CONF_PATH="${REFIND_CONF_PATH:-}"
# Without an explicit resolution, rEFInd auto-picks a GOP mode that often
# doesn't match the real display, so the theme's fullscreen banner and icons
# render distorted/misplaced. Matches fedora-refind-setup.sh's default for
# the same ultrawide display. Set to "" to leave whatever resolution setting
# (or lack of one) is already in your refind.conf alone.
REFIND_RESOLUTION_WIDTH="${REFIND_RESOLUTION_WIDTH:-3440}"
REFIND_RESOLUTION_HEIGHT="${REFIND_RESOLUTION_HEIGHT:-1440}"
# On a non-UKI setup, rEFInd's loose-kernel scan (vmlinuz found directly in
# /boot rather than a bootloader-binary directory) only picks up a
# distro-specific icon if this exact file is present — otherwise it falls
# back to a generic Linux icon. Harmless no-op if you're on UKI, since there's
# no loose-kernel entry for it to apply to.
REFIND_VOLUME_ICON_SOURCE="${REFIND_VOLUME_ICON_SOURCE:-icons/os_arch.png}"
REFIND_VOLUME_ICON_DEST="${REFIND_VOLUME_ICON_DEST:-/boot/.VolumeIcon.png}"

# Hardware-specific quirk, not a universal need: many boards' watchdog chips
# can't be cleanly disarmed on shutdown, so the kernel logs "watchdog did not
# stop!" every time — harmless but noisy. Set DISABLE_HARDWARE_WATCHDOG=0 if
# your hardware doesn't hit this.
#
# nowatchdog (kernel cmdline) only disables the kernel's own lockup NMI
# detector — it does NOT reliably stop a hardware watchdog timer chip from
# arming in the first place. Blacklisting the actual driver module is what
# stops the shutdown warning; nowatchdog is added too as a harmless
# companion setting. The two listed below cover the large majority of
# desktop Intel/AMD chipsets — check `dmesg | grep -i watchdog` on your
# machine if yours isn't one of these and add it to the list.
DISABLE_HARDWARE_WATCHDOG="${DISABLE_HARDWARE_WATCHDOG:-1}"
WATCHDOG_MODULES_TO_BLACKLIST="${WATCHDOG_MODULES_TO_BLACKLIST:-iTCO_wdt iTCO_vendor_support sp5100_tco}"
# Only applies to a non-UKI rEFInd setup, since that's where the kernel
# cmdline lives in a plain-text refind_linux.conf.
REFIND_LINUX_CONF_PATH="${REFIND_LINUX_CONF_PATH:-/boot/refind_linux.conf}"

# Noctalia is installed from the AUR (there is no COPR equivalent). Uses the
# stable release, not the bleeding-edge "-git" build (unlike the Fedora
# script, which still tracks noctalia-git).
NOCTALIA_PACKAGE="${NOCTALIA_PACKAGE:-noctalia}"
NOCTALIA_GREETER_PACKAGE="${NOCTALIA_GREETER_PACKAGE:-noctalia-greeter}"
NAUTILUS_OPEN_ANY_TERMINAL_PACKAGE="${NAUTILUS_OPEN_ANY_TERMINAL_PACKAGE:-nautilus-open-any-terminal}"
NAUTILUS_TERMINAL="${NAUTILUS_TERMINAL:-alacritty}"
VSCODE_PACKAGE="${VSCODE_PACKAGE:-visual-studio-code-bin}"
# LACT is in the official Arch repos as of mid-2026 (no COPR/AUR needed,
# unlike Fedora).
LACT_PACKAGE="${LACT_PACKAGE:-lact}"
# arch-update is AUR-only (no official-repo build). Its optional deps include
# the configured AUR helper and flatpak, so it picks up AUR/Flatpak update
# checks automatically once those are present — nothing extra to configure
# here for that.
ARCH_UPDATE_PACKAGE="${ARCH_UPDATE_PACKAGE:-arch-update}"
# The mcmojave-cursors AUR package installs to /usr/share/icons/mcmojave-cursors
# (lowercase, matching the pkgname) regardless of TARGET_USER, so no per-user
# install step or clone directory is needed here.
MCMOJAVE_CURSORS_PACKAGE="${MCMOJAVE_CURSORS_PACKAGE:-mcmojave-cursors}"
MCMOJAVE_CURSOR_THEME="${MCMOJAVE_CURSOR_THEME:-mcmojave-cursors}"

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
LOG_FILE="${LOG_FILE:-$HOME/arch-niri-setup-$TIMESTAMP.log}"
USER_BACKUP_ROOT="${USER_BACKUP_ROOT:-$HOME/.local/share/arch-niri-setup/backups/$TIMESTAMP}"
SYSTEM_BACKUP_ROOT="${SYSTEM_BACKUP_ROOT:-/var/backups/arch-niri-setup/$TIMESTAMP}"

TARGET_HOME="$HOME"
PACMAN_BIN="${PACMAN_BIN:-pacman}"
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
  printf '%s  │  %sArch Niri Setup%s                                     │%s\n' "$COLOR_BLUE" "$COLOR_BOLD" "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  │  %sNiri desktop installer for Arch Linux%s               │%s\n' "$COLOR_BLUE" "$COLOR_DIM" "$COLOR_BLUE" "$COLOR_RESET"
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
  "$PACMAN_BIN" -Q "$1" >/dev/null 2>&1
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

require_arch() {
  [[ "$EUID" -ne 0 ]] || die "Run this script as your normal user, not directly as root."

  if [[ ! -f /etc/arch-release ]] && ! grep -qi '^ID=arch$' /etc/os-release 2>/dev/null; then
    die "This script is intended for Arch Linux."
  fi

  have_command "$PACMAN_BIN" || die "$PACMAN_BIN was not found."
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
    CONFIG_REPO_DIR="$TARGET_HOME/.cache/arch-niri-setup/linux-niri"
  fi

  if [[ "$USER_BACKUP_ROOT_WAS_SET" == "0" ]]; then
    USER_BACKUP_ROOT="$TARGET_HOME/.local/share/arch-niri-setup/backups/$TIMESTAMP"
  fi

  if [[ "$CONFIG_SOURCE_DIR_WAS_SET" == "0" ]]; then
    CONFIG_SOURCE_DIR="$CONFIG_REPO_DIR"
  fi

  if [[ "$REFIND_THEME_DIR_WAS_SET" == "0" ]]; then
    REFIND_THEME_DIR="$TARGET_HOME/.cache/arch-niri-setup/refind-theme"
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

# This script assumes rEFInd is already installed and configured (e.g. via
# archinstall) -- checked here, up front, so a machine without rEFInd fails
# fast instead of only finding out after installing every other package.
# find_refind_conf() is defined further down (it also does the real theming
# work later); forward-referencing it here is fine since main() doesn't call
# this until after the whole script has been parsed.
require_refind() {
  [[ "$INSTALL_REFIND_THEME" == "1" ]] || {
    log "rEFInd theming is disabled (INSTALL_REFIND_THEME=0); skipping the rEFInd requirement check."
    return 0
  }

  log "Checking for an existing rEFInd installation (this script assumes rEFInd is already set up, e.g. via archinstall)."
  find_refind_conf >/dev/null || die "This script assumes rEFInd is already installed and configured (e.g. via archinstall), but no refind.conf was found (searched /boot, /boot/efi, /efi, and any mounted vfat filesystem). Install and configure rEFInd first, set REFIND_CONF_PATH to its exact location if it's somewhere unusual, or set INSTALL_REFIND_THEME=0 to run this script without rEFInd."
  log "Found an existing rEFInd installation."
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

pacman_install() {
  local packages=("$@")
  local args=(-S --needed)

  [[ "$ASSUME_YES" == "1" ]] && args+=(--noconfirm)

  run_sudo "$PACMAN_BIN" "${args[@]}" "${packages[@]}"
}

pacman_install_optional() {
  if pacman_install "$@"; then
    return 0
  fi

  warn "Could not install optional package set: $*"
  return 1
}

pacman_install_best_effort() {
  local packages=("$@")
  local package
  local failed=0

  if pacman_install "${packages[@]}"; then
    return 0
  fi

  warn "Batch package install failed; retrying packages one at a time and skipping failures."
  for package in "${packages[@]}"; do
    if ! pacman_install_optional "$package"; then
      failed=1
    fi
  done

  if [[ "$failed" == "1" ]]; then
    warn "Some packages could not be installed. Continuing so later setup steps can run."
  fi

  return 0
}

ensure_aur_helper() {
  if have_command "$AUR_HELPER"; then
    log "$AUR_HELPER is already installed."
    return 0
  fi

  log "Bootstrapping AUR helper: $AUR_HELPER."
  pacman_install_best_effort base-devel git

  local build_dir="$TARGET_HOME/.cache/arch-niri-setup/aur-helper/$AUR_HELPER"
  run_as_user mkdir -p "$(dirname "$build_dir")"
  safe_rm_rf "$build_dir"
  run_as_user git clone "https://aur.archlinux.org/${AUR_HELPER}.git" "$build_dir"

  (cd "$build_dir" && run_as_user makepkg -si --noconfirm --needed) || \
    die "Failed to build and install $AUR_HELPER from the AUR. Check the output above."

  have_command "$AUR_HELPER" || die "$AUR_HELPER installation finished, but it was not found in PATH."
  record_change "Bootstrapped the $AUR_HELPER AUR helper."
}

aur_install() {
  local packages=("$@")
  local args=(-S --needed)

  [[ "$ASSUME_YES" == "1" ]] && args+=(--noconfirm)

  run_as_user "$AUR_HELPER" "${args[@]}" "${packages[@]}"
}

aur_install_optional() {
  if aur_install "$@"; then
    return 0
  fi

  warn "Could not install optional AUR package set: $*"
  return 1
}

aur_install_best_effort() {
  local packages=("$@")
  local package
  local failed=0

  if aur_install "${packages[@]}"; then
    return 0
  fi

  warn "Batch AUR install failed; retrying packages one at a time and skipping failures."
  for package in "${packages[@]}"; do
    if ! aur_install_optional "$package"; then
      failed=1
    fi
  done

  if [[ "$failed" == "1" ]]; then
    warn "Some AUR packages could not be installed. Continuing so later setup steps can run."
  fi

  return 0
}

install_arch_packages() {
  local packages=(
    base-devel
    git
    git-lfs
    github-cli
    curl
    tar
    xz
    niri
    greetd
    alacritty
    ttf-jetbrains-mono
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
    qt5-wayland
    qt6-wayland
    qt6-base
    qt6-declarative
    pipewire
    wireplumber
    pipewire-pulse
    pipewire-alsa
    pipewire-jack
    pavucontrol
  )

  if [[ -n "$EXTRA_ARCH_PACKAGES" ]]; then
    local extra_packages=()
    read -r -a extra_packages <<<"$EXTRA_ARCH_PACKAGES"
    packages+=("${extra_packages[@]}")
  fi

  log "Installing Arch packages with $PACMAN_BIN."
  pacman_install_best_effort "${packages[@]}"
  record_change "Installed or attempted Arch packages for a basic Niri desktop."
}

enable_multilib() {
  [[ "$ENABLE_MULTILIB" == "1" ]] || {
    log "multilib repository enablement is disabled."
    return 0
  }

  local path="/etc/pacman.conf"

  if run_sudo grep -qE '^\[multilib\]' "$path"; then
    log "multilib repository is already enabled."
    return 0
  fi

  if ! run_sudo grep -qE '^#\[multilib\]' "$path"; then
    warn "Could not find a commented [multilib] section in $path; enable it manually."
    return 1
  fi

  log "Enabling the multilib repository."
  backup_system_path "$path"

  local tmp; tmp="$(mktemp)"
  run_sudo awk '
    /^#\[multilib\]/ { print substr($0, 2); armed = 1; next }
    armed && /^#Include/ { print substr($0, 2); armed = 0; next }
    { print }
  ' "$path" >"$tmp"

  run_sudo install -m 0644 "$tmp" "$path"
  rm -f "$tmp"

  run_sudo "$PACMAN_BIN" -Sy || warn "pacman -Sy failed after enabling multilib."
  record_change "Enabled the multilib repository."
}

install_flatpak() {
  [[ "$INSTALL_FLATPAK" == "1" ]] || {
    log "Flatpak installation is disabled."
    return 0
  }

  log "Installing Flatpak."
  if ! pacman_install_optional flatpak; then
    return 0
  fi
  record_change "Installed Flatpak."

  [[ "$ADD_FLATHUB_REMOTE" == "1" ]] || {
    log "Flathub remote setup is disabled."
    return 0
  }

  # System-wide (not --user), matching pacman's system-wide package scope
  # used everywhere else in this script — makes Flathub apps available to
  # any user on the machine, not just TARGET_USER.
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

detect_gpu_vendors() {
  # pciutils isn't in the base package list (most machines already have it),
  # but install it best-effort here rather than silently giving up detection
  # to a fallback whenever it's genuinely missing.
  have_command lspci || pacman_install_best_effort pciutils
  have_command lspci || return 0

  local pci_out
  pci_out="$(lspci -k 2>/dev/null | grep -iE 'VGA compatible controller|3D controller|Display controller' || true)"

  grep -qi 'AMD\|ATI' <<<"$pci_out" && printf 'amd\n'
  grep -qi 'Intel' <<<"$pci_out" && printf 'intel\n'
  grep -qi 'NVIDIA' <<<"$pci_out" && printf 'nvidia\n'

  return 0
}

install_steam_graphics_deps() {
  [[ "$INSTALL_STEAM_GRAPHICS_DEPS" == "1" ]] || {
    log "Steam 32-bit graphics dependency installation is disabled."
    return 0
  }

  local packages=(lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader)
  local vendors=()
  mapfile -t vendors < <(detect_gpu_vendors)

  if [[ "${#vendors[@]}" -eq 0 ]]; then
    warn "Could not detect a GPU vendor via lspci; installing AMD and Intel Vulkan drivers as a safe default. If this machine has an Nvidia GPU, install nvidia-utils and lib32-nvidia-utils manually."
    vendors=(amd intel)
  fi

  local vendor
  for vendor in "${vendors[@]}"; do
    case "$vendor" in
      amd) packages+=(vulkan-radeon lib32-vulkan-radeon) ;;
      intel) packages+=(vulkan-intel lib32-vulkan-intel) ;;
      nvidia) packages+=(nvidia-utils lib32-nvidia-utils) ;;
    esac
  done

  log "Installing 32-bit Mesa/Vulkan packages needed for Steam/Proton games: ${packages[*]}."
  pacman_install_best_effort "${packages[@]}"
  record_change "Installed 32-bit graphics packages for Steam gaming (${packages[*]})."
}

install_steam() {
  [[ "$INSTALL_STEAM" == "1" ]] || {
    log "Steam installation is disabled."
    return 0
  }

  enable_multilib
  install_steam_graphics_deps

  log "Installing Steam."
  if pacman_install_optional steam; then
    record_change "Installed Steam."
  fi

  install_gamescope
}

install_gamescope() {
  [[ "$INSTALL_GAMESCOPE" == "1" ]] || {
    log "gamescope installation is disabled."
    return 0
  }

  log "Installing gamescope."
  if pacman_install_optional gamescope; then
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

install_vscode() {
  [[ "$INSTALL_VSCODE" == "1" ]] || {
    log "VS Code installation is disabled."
    return 0
  }

  log "Installing Visual Studio Code ($VSCODE_PACKAGE) from the AUR."
  if aur_install_optional "$VSCODE_PACKAGE"; then
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

  log "Installing McMojave cursors ($MCMOJAVE_CURSORS_PACKAGE) from the AUR."
  if aur_install_optional "$MCMOJAVE_CURSORS_PACKAGE"; then
    record_change "Installed McMojave cursor theme ($MCMOJAVE_CURSORS_PACKAGE) from the AUR."
  fi
}

find_refind_conf() {
  if [[ -n "$REFIND_CONF_PATH" ]]; then
    if run_sudo test -f "$REFIND_CONF_PATH"; then
      printf '%s\n' "$REFIND_CONF_PATH"
      return 0
    fi
    warn "REFIND_CONF_PATH=$REFIND_CONF_PATH does not exist; falling back to searching for it."
  fi

  # Search actual mount points rather than guessing a fixed path — ESP
  # layout varies (mounted at /boot, /boot/efi, /efi, or elsewhere; rEFInd
  # itself may live under EFI/refind/, EFI/BOOT/, or elsewhere on the ESP).
  local roots=(/boot /boot/efi /efi)
  local vfat_target
  while IFS= read -r vfat_target; do
    [[ -n "$vfat_target" ]] || continue
    roots+=("$vfat_target")
  done < <(findmnt -rn -o TARGET --types vfat 2>/dev/null || true)

  local root hit
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    hit="$(run_sudo find "$root" -maxdepth 4 -iname 'refind.conf' 2>/dev/null | head -1)"
    [[ -n "$hit" ]] && { printf '%s\n' "$hit"; return 0; }
  done

  return 1
}

install_refind_theme() {
  [[ "$INSTALL_REFIND_THEME" == "1" ]] || {
    log "rEFInd theme installation is disabled."
    return 0
  }

  # require_refind() should already have confirmed this exists during
  # preflight; re-checking here rather than trusting that (in case
  # something changed the ESP mid-run) is a hard failure, not a graceful
  # skip, since by this point we've already told the user rEFInd is required.
  local refind_conf
  refind_conf="$(find_refind_conf || true)"
  [[ -n "$refind_conf" ]] || die "refind.conf could not be located anymore (it was found during preflight). Searched /boot, /boot/efi, /efi, and any mounted vfat filesystem."

  # Independent of whether the theme itself installs below -- a resolution
  # fix is a real improvement even if the theme repo fails to clone.
  configure_refind_resolution "$refind_conf"

  log "Fetching rEFInd theme from $REFIND_THEME_REPO."
  clone_or_update_git_repo "$REFIND_THEME_REPO" "$REFIND_THEME_DIR"

  [[ -f "$REFIND_THEME_DIR/theme.conf" ]] || {
    warn "$REFIND_THEME_DIR has no theme.conf; not a valid rEFInd theme, skipping."
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
  # -r, not -a: the ESP is vfat, which has no concept of Unix ownership —
  # cp -a always fails trying to chown there, even as root.
  run_sudo mkdir -p "$theme_dest"
  run_sudo cp -r "$tmp_theme/." "$theme_dest/"
  rm -rf "$tmp_theme"

  run_sudo test -f "$theme_dest/theme.conf" || \
    die "Theme copy to $theme_dest failed — theme.conf missing after copy."

  log "Installed rEFInd theme '$REFIND_THEME_NAME' to $theme_dest."
  record_change "Installed rEFInd theme '$REFIND_THEME_NAME' from $REFIND_THEME_REPO."

  local icon_src="$theme_dest/$REFIND_VOLUME_ICON_SOURCE"
  if run_sudo test -f "$icon_src"; then
    backup_system_path "$REFIND_VOLUME_ICON_DEST"
    run_sudo install -d -m 0755 "$(dirname "$REFIND_VOLUME_ICON_DEST")"
    run_sudo cp "$icon_src" "$REFIND_VOLUME_ICON_DEST"
    log "Installed rEFInd volume icon to $REFIND_VOLUME_ICON_DEST."
    record_change "Set $REFIND_VOLUME_ICON_DEST from the theme's $REFIND_VOLUME_ICON_SOURCE."
  else
    warn "$icon_src not found in the theme; skipping the rEFInd volume icon (loose-kernel boot entries will keep a generic icon)."
  fi

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

# Only touches rEFInd's resolution setting -- nothing else in refind.conf
# (scanfor, dont_scan_dirs, timeout, existing menu entries) is managed by
# this script, unlike fedora-refind-setup.sh's fuller boot-entry config,
# since this script assumes an already-configured rEFInd it shouldn't
# otherwise disturb.
configure_refind_resolution() {
  local refind_conf="$1"

  [[ -n "$REFIND_RESOLUTION_WIDTH" && -n "$REFIND_RESOLUTION_HEIGHT" ]] || {
    log "REFIND_RESOLUTION_WIDTH/HEIGHT not set; leaving rEFInd's resolution setting as-is."
    return 0
  }

  local marker_begin="# BEGIN arch-niri-setup generated resolution"
  local marker_end="# END arch-niri-setup generated resolution"

  backup_system_path "$refind_conf"
  local tmp; tmp="$(mktemp)"
  run_sudo awk -v marker_begin="$marker_begin" -v marker_end="$marker_end" '
    $0 == marker_begin { skipping = 1; next }
    $0 == marker_end   { skipping = 0; next }
    !skipping { print }
  ' "$refind_conf" >"$tmp"

  [[ -s "$tmp" ]] && printf '\n' >>"$tmp"
  cat >>"$tmp" <<EOF
$marker_begin
resolution $REFIND_RESOLUTION_WIDTH $REFIND_RESOLUTION_HEIGHT
$marker_end
EOF

  run_sudo install -m 0644 "$tmp" "$refind_conf"
  rm -f "$tmp"

  log "Set rEFInd resolution to ${REFIND_RESOLUTION_WIDTH}x${REFIND_RESOLUTION_HEIGHT} in $refind_conf."
  record_change "Set rEFInd resolution to ${REFIND_RESOLUTION_WIDTH}x${REFIND_RESOLUTION_HEIGHT} in $refind_conf (without this, rEFInd auto-picks a GOP mode that often doesn't match the real display, distorting the theme's banner/icons)."
}

disable_hardware_watchdog() {
  [[ "$DISABLE_HARDWARE_WATCHDOG" == "1" ]] || {
    log "Hardware watchdog disabling is disabled."
    return 0
  }

  if [[ -n "$WATCHDOG_MODULES_TO_BLACKLIST" ]]; then
    local module blacklist_lines=""
    for module in $WATCHDOG_MODULES_TO_BLACKLIST; do
      blacklist_lines+="blacklist $module"$'\n'
    done
    printf '%s' "$blacklist_lines" | write_system_file /etc/modprobe.d/watchdog-blacklist.conf 0644
    log "Blacklisted hardware watchdog modules: $WATCHDOG_MODULES_TO_BLACKLIST."
    record_change "Blacklisted hardware watchdog modules ($WATCHDOG_MODULES_TO_BLACKLIST) in /etc/modprobe.d/watchdog-blacklist.conf. Takes effect on next boot — blacklisting doesn't unload an already-loaded module."
  fi

  local path="$REFIND_LINUX_CONF_PATH"
  run_sudo test -f "$path" || {
    warn "$path not found; skipping the nowatchdog kernel parameter (only applies to a non-UKI rEFInd setup)."
    return 0
  }

  if run_sudo grep -q 'nowatchdog' "$path"; then
    log "nowatchdog already present in $path."
    return 0
  fi

  backup_system_path "$path"
  local tmp; tmp="$(mktemp)"
  run_sudo awk '
    /^"[^"]*"[[:space:]]+"[^"]*"[[:space:]]*$/ {
      sub(/"[[:space:]]*$/, " nowatchdog\"")
    }
    { print }
  ' "$path" >"$tmp"
  run_sudo install -m 0644 "$tmp" "$path"
  rm -f "$tmp"

  log "Added nowatchdog to every boot option line in $path."
  record_change "Added the nowatchdog kernel parameter to $path (suppresses a harmless 'watchdog did not stop' shutdown warning)."
}

install_nautilus_open_any_terminal() {
  [[ "$INSTALL_NAUTILUS_OPEN_ANY_TERMINAL" == "1" ]] || {
    log "Nautilus Open Any Terminal installation is disabled."
    return 0
  }

  if aur_install_optional "$NAUTILUS_OPEN_ANY_TERMINAL_PACKAGE"; then
    record_change "Installed Nautilus Open Any Terminal."
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

  if ! pacman_install_optional "$LACT_PACKAGE"; then
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

install_arch_update() {
  [[ "$INSTALL_ARCH_UPDATE" == "1" ]] || {
    log "arch-update installation is disabled."
    return 0
  }

  if ! aur_install_optional "$ARCH_UPDATE_PACKAGE"; then
    return 0
  fi
  record_change "Installed arch-update ($ARCH_UPDATE_PACKAGE) for pacman/AUR/Flatpak update notifications."

  [[ "$ENABLE_ARCH_UPDATE_TIMER" == "1" ]] || {
    log "arch-update background timer autostart is disabled."
    return 0
  }

  if set_systemd_user_service arch-update.timer; then
    record_change "Enabled the arch-update background update-check timer."
  fi
}

install_default_apps() {
  install_vscode
  install_steam
  install_mcmojave_cursors
  install_nautilus_open_any_terminal
  install_lact
  install_arch_update
  install_proton_mail
  install_localsend
  install_protonup_qt
}

install_noctalia_packages() {
  log "Installing Noctalia v5 and Noctalia Greeter from the AUR."
  aur_install "$NOCTALIA_PACKAGE" "$NOCTALIA_GREETER_PACKAGE"

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
  write_user_file "$TARGET_HOME/.config/environment.d/10-arch-niri-setup.conf" 0644 <<EOF
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
    --shell /usr/bin/nologin \
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
  section "Arch Niri setup"
  require_arch
  resolve_target_user
  prepare_runtime
  require_refind

  section "Base packages"
  install_arch_packages
  install_flatpak
  ensure_aur_helper

  section "Default apps"
  install_default_apps

  section "rEFInd"
  install_refind_theme
  disable_hardware_watchdog

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
