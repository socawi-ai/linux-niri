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
# fedora-third-party enable turns on every bundled third-party repo at once
# (there's no per-repo flag on the tool itself); Google Chrome's is disabled
# back off right after, since it's not wanted on this machine.
ENABLE_GOOGLE_CHROME_REPO="${ENABLE_GOOGLE_CHROME_REPO:-0}"
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

# Set up last, after the desktop. A failure in one of these is reported as a
# warning and the rest still run; re-run the script once it's fixed.
#   INSTALL_REFIND   -- themed rEFInd boot menu that boots the kernels
#                       directly; GRUB stays as the fallback (see rEFInd
#                       below). UEFI with Secure Boot off only.
#   INSTALL_LSFG_VK  -- builds lsfg-vk from source (needs Lossless Scaling on
#                       Steam to be useful).
#   INSTALL_SUNSHINE -- Sunshine streaming host, set to start on login.
#
# steam-sunshine-sync.sh is not run from here: it needs Steam logged in and
# games installed first. Run it on its own afterwards (the summary says so).
INSTALL_REFIND="${INSTALL_REFIND:-1}"
INSTALL_LSFG_VK="${INSTALL_LSFG_VK:-1}"
INSTALL_SUNSHINE="${INSTALL_SUNSHINE:-1}"

# rEFInd is installed as an ADDITIONAL firmware boot entry, first in the boot
# order, themed with rEFInd-nils. It boots the kernels in /boot directly
# (firmware -> rEFInd -> kernel), with the options in /boot/refind_linux.conf.
# GRUB stays installed but is only the fallback: Fedora's own "Fedora" entry
# (shim -> GRUB) is left in place, so the firmware boot menu can always pick it.
#
# Secure Boot must be off: this rEFInd is unsigned, and Fedora's shim 16 can't
# load rEFInd 0.14.2 anyway (misaligned .sbat section; rhboot/shim#803). With
# Secure Boot on, rEFInd is skipped and GRUB stays the boot menu.
#
# rEFInd has no Fedora/COPR package; upstream ships version-pinned RPMs on
# SourceForge with no "latest" alias, so the version is pinned here.
REFIND_VERSION="${REFIND_VERSION:-0.14.2}"
REFIND_RPM_URL="${REFIND_RPM_URL:-https://sourceforge.net/projects/refind/files/${REFIND_VERSION}/refind-${REFIND_VERSION}-1.x86_64.rpm/download}"
# Confirmed to ship icons/os_fedora.png.
REFIND_THEME_REPO="${REFIND_THEME_REPO:-https://github.com/NilsPvR/rEFInd-nils}"
REFIND_THEME_NAME="${REFIND_THEME_NAME:-rEFInd-nils}"
# Defaults under the target user's home, set in resolve_target_user.
REFIND_THEME_DIR="${REFIND_THEME_DIR:-}"
# Explicit overrides if refind.conf or the ESP can't be found automatically.
REFIND_CONF_PATH="${REFIND_CONF_PATH:-}"
ESP_MOUNT_OVERRIDE="${ESP_MOUNT_OVERRIDE:-}"
# The shim Fedora's own firmware entry boots, relative to the ESP root. Only
# used to recognize the ESP.
REFIND_SHIM_LOADER_PATH="${REFIND_SHIM_LOADER_PATH:-/EFI/fedora/shimx64.efi}"
# Relative to refind.conf's directory. Copied next to each kernel in /boot as
# vmlinuz-<version>.png (rEFInd's per-loader icon), else it shows Tux.
REFIND_KERNEL_ICON="${REFIND_KERNEL_ICON:-themes/$REFIND_THEME_NAME/icons/os_fedora.png}"
# "internal" finds the kernels in /boot and other OSes (e.g. Windows) on
# internal disks; "external,optical" keeps USB installers/rescue disks visible.
REFIND_SCANFOR="${REFIND_SCANFOR:-manual,internal,external,optical}"
# Skipped by that scan: Fedora's shim/GRUB (the fallback, reachable from
# the firmware boot menu) and EFI/BOOT (the generic fallback loader). Set to
# "" to scan everything.
REFIND_DONT_SCAN_DIRS="${REFIND_DONT_SCAN_DIRS:-EFI/fedora,EFI/BOOT}"
REFIND_TIMEOUT_SECONDS="${REFIND_TIMEOUT_SECONDS:-10}"
# Without an explicit resolution rEFInd often picks a mode that doesn't match
# the display, and the theme renders distorted. Matches GRUB_GFXMODE's first
# mode below; set either to "" for rEFInd's own auto-detect.
REFIND_RESOLUTION_WIDTH="${REFIND_RESOLUTION_WIDTH:-3440}"
REFIND_RESOLUTION_HEIGHT="${REFIND_RESOLUTION_HEIGHT:-1440}"
# Installed so new kernels get the icon too; it also removes icons of
# kernels that are gone.
REFIND_ICON_HOOK="${REFIND_ICON_HOOK:-/etc/kernel/install.d/95-refind-icons.install}"

# lsfg-vk (https://lsfg-vk.dev): a Vulkan layer running Lossless Scaling's
# frame generation, built per the official "Building from Source" guide for
# Fedora. Re-running updates and rebuilds it.
LSFG_VK_REPO_URL="${LSFG_VK_REPO_URL:-https://git.lsfg-vk.dev/lsfg-vk.git}"
# Empty = the latest default branch.
LSFG_VK_REPO_TAG="${LSFG_VK_REPO_TAG:-}"
# Defaults under the target user's home, set in resolve_target_user.
LSFG_VK_BUILD_DIR="${LSFG_VK_BUILD_DIR:-}"
LSFG_VK_INSTALL_PREFIX="${LSFG_VK_INSTALL_PREFIX:-/usr/local}"
LSFG_VK_BUILD_TYPE="${LSFG_VK_BUILD_TYPE:-Release}"
LSFG_VK_ENABLE_LTO="${LSFG_VK_ENABLE_LTO:-1}"
LSFG_VK_BUILD_UI="${LSFG_VK_BUILD_UI:-1}"
# vulkan-tools ships vkcube, to check the layer loads.
INSTALL_VULKAN_TOOLS="${INSTALL_VULKAN_TOOLS:-1}"

# Sunshine from LizardByte's COPR. The native package, not the Flatpak:
# Flatpak's sandbox can't do the KMS capture a bare niri session needs.
SUNSHINE_COPR="${SUNSHINE_COPR:-lizardbyte/stable}"
ENABLE_SUNSHINE_AUTOSTART="${ENABLE_SUNSHINE_AUTOSTART:-1}"
# The connector Sunshine streams (find names with: niri msg outputs).
SUNSHINE_CAPTURE_OUTPUT="${SUNSHINE_CAPTURE_OUTPUT:-DP-2}"
# Defaults under the target user's home, set in resolve_target_user.
SUNSHINE_CONFIG_DIR="${SUNSHINE_CONFIG_DIR:-}"

# What the script does:
#   full    -- the whole setup: packages, apps, boot, configs, greeter, ...
#   configs -- only fetch this repo and put its configs and wallpapers in
#              place (niri, Alacritty, Noctalia), replacing the local ones.
#              No sudo, no packages. Same as --configs-only.
# The setup menu asks, unless SETUP_MODE or --configs-only already says.
SETUP_MODE="${SETUP_MODE:-}"

# The setup menu: the mode, then for a full install a checklist of the
# optional features below (pre-checked from the INSTALL_*/... values above,
# so environment variables still set the defaults), shown when there's a
# terminal. SETUP_MENU=0 or --no-menu skips it and uses those values as
# they are (and SETUP_MODE, or full), e.g. for unattended runs.
SETUP_MENU="${SETUP_MENU:-1}"

# While installing, show a progress gauge (same look as the menu) instead
# of every command's output, which then goes only to the log. Needs a
# terminal, and ASSUME_YES=1 (the default): with ASSUME_YES=0 the script
# asks questions on the terminal, which the gauge would cover.
# PROGRESS_UI=0 or --verbose shows the full output instead.
PROGRESS_UI="${PROGRESS_UI:-1}"

# "tag|variable|label" -- the menu's optional features, in menu order. The
# core (Niri, Noctalia, base packages, this repo's configs) is always set up.
SETUP_FEATURES=(
  "steam|INSTALL_STEAM|Steam (RPM Fusion)"
  "gamescope|INSTALL_GAMESCOPE|gamescope (Valve's game compositor)"
  "lact|INSTALL_LACT|LACT (GPU control, lactd service)"
  "vscode|INSTALL_VSCODE|Visual Studio Code"
  "flatpak|INSTALL_FLATPAK|Flatpak + Flathub"
  "protonmail|INSTALL_PROTON_MAIL|Proton Mail (Flatpak)"
  "localsend|INSTALL_LOCALSEND|LocalSend (Flatpak)"
  "protonupqt|INSTALL_PROTONUP_QT|ProtonUp-Qt (Flatpak)"
  "cursors|INSTALL_MCMOJAVE_CURSORS|McMojave cursors"
  "nautilusterm|INSTALL_NAUTILUS_OPEN_ANY_TERMINAL|Nautilus: Open in Alacritty"
  "greeter|ENABLE_GREETD|Login screen (greetd + Noctalia Greeter)"
  "plymouth|CONFIGURE_PLYMOUTH|Boot splash and GRUB look (Plymouth)"
  "watchdog|DISABLE_HARDWARE_WATCHDOG|Silence the watchdog shutdown warning"
  "refind|INSTALL_REFIND|rEFInd boot menu (themed)"
  "lsfg|INSTALL_LSFG_VK|lsfg-vk frame generation (build from source)"
  "sunshine|INSTALL_SUNSHINE|Sunshine streaming host"
)

# The same whiptail theme as steam-sunshine-sync.sh: white dialog, black
# text, green buttons, red for whatever has focus -- readable in any
# terminal palette. Left alone if NEWT_COLORS is already set.
NEWT_COLORS="${NEWT_COLORS:-root=,black
window=black,white
border=black,white
title=black,white
label=black,white
listbox=black,white
actlistbox=white,red
checkbox=black,white
actcheckbox=white,red
button=black,green
actbutton=white,red
entry=black,white
textbox=black,white
acttextbox=white,red
helpline=white,black
roottext=white,black}"
export NEWT_COLORS
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
# Around the generated part of refind.conf. Named after the former
# fedora-refind-setup.sh, so machines set up by it are still recognized.
REFIND_MARKER_BEGIN="# BEGIN fedora-refind-setup generated boot configuration"
REFIND_MARKER_END="# END fedora-refind-setup generated boot configuration"

# Hardware-specific quirk, not a universal need: many boards' watchdog chips
# can't be cleanly disarmed on shutdown, so the kernel logs "watchdog did not
# stop!" every time -- harmless but noisy. Set DISABLE_HARDWARE_WATCHDOG=0 if
# your hardware doesn't hit this.
#
# nowatchdog (kernel cmdline) only disables the kernel's own lockup NMI
# detector -- it does NOT reliably stop a hardware watchdog timer chip from
# arming in the first place. Blacklisting the actual driver module is what
# stops the shutdown warning; nowatchdog is added too as a harmless
# companion setting, via grubby (already used by the Plymouth setup above).
# The two listed below cover the large majority of desktop Intel/AMD
# chipsets -- check `dmesg | grep -i watchdog` on your machine if yours
# isn't one of these and add it to the list.
DISABLE_HARDWARE_WATCHDOG="${DISABLE_HARDWARE_WATCHDOG:-1}"
WATCHDOG_MODULES_TO_BLACKLIST="${WATCHDOG_MODULES_TO_BLACKLIST:-iTCO_wdt iTCO_vendor_support sp5100_tco}"
NOCTALIA_CONFIG_FILE="${NOCTALIA_CONFIG_FILE:-settings.toml}"
NOCTALIA_CONFIG_RELATIVE_DIR="${NOCTALIA_CONFIG_RELATIVE_DIR:-.local/state/noctalia}"
NOCTALIA_WALLPAPER_FILE="${NOCTALIA_WALLPAPER_FILE:-vpoem3.jpg}"
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
STEP_TITLE=""
# The progress gauge's input and process, and the terminal-and-log output
# to go back to, while it's shown.
PROGRESS_FD=""
PROGRESS_PID=""
PROGRESS_SAVED_OUT=""

# Set by the rEFInd, lsfg-vk and Sunshine steps, for the summary.
ESP_MOUNT=""
REFIND_BOOT_NUM=""
SECURE_BOOT_STATE="unknown"
REFIND_INSTALLED=0
LSFG_VK_INSTALLED=0
SUNSHINE_INSTALLED=0

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

TOTAL_SECTIONS=10

declare -a CHANGES=()
declare -a WARNINGS=()
declare -a USER_BACKUPS=()
declare -a SYSTEM_BACKUPS=()

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
  STEP_TITLE="$*"
  progress_update ""
  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_BLUE" "$COLOR_RESET"
  printf '%s  [ %02d / %02d ]  %s%s\n' "$COLOR_BLUE" "$STEP_COUNT" "$TOTAL_SECTIONS" "$*" "$COLOR_RESET"
  printf '%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_BLUE" "$COLOR_RESET"
}

log() {
  printf '  %s✓%s  %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"
  progress_update "$*"
}

warn() {
  WARNINGS+=("$*")
  printf '  %s⚠%s  %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
  progress_update "Warning: $*"
}

die() {
  stop_progress
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

  REFIND_THEME_DIR="${REFIND_THEME_DIR:-$TARGET_HOME/.cache/fedora-niri-setup/refind-theme}"
  LSFG_VK_BUILD_DIR="${LSFG_VK_BUILD_DIR:-$TARGET_HOME/.cache/fedora-niri-setup/lsfg-vk}"
  SUNSHINE_CONFIG_DIR="${SUNSHINE_CONFIG_DIR:-$TARGET_HOME/.config/sunshine}"

  log "Target user: $TARGET_USER"
  log "Target home: $TARGET_HOME"
  log "Config repo: $CONFIG_REPO_URL"
  log "Config source: $CONFIG_SOURCE_DIR"
}

usage() {
  cat <<EOF
Usage: fedora-niri-setup.sh [options]

Sets up a Niri desktop on Fedora, or only updates this repo's configs on
it. Run from a terminal, a menu asks which, and for a full install which
optional features to set up.

Options:
  --configs-only  Only fetch this repo and put its configs and wallpapers
                  in place; no sudo, no packages (same as SETUP_MODE=configs)
  --no-menu       Skip the menu; use the defaults and INSTALL_*/...
                  environment variables as they are (same as SETUP_MENU=0)
  --verbose       Show every command's output instead of a progress gauge
                  (same as PROGRESS_UI=0)
  -h, --help      Show this help and exit

See the top of the script for all environment variables.
EOF
}

# Everything from here on also goes to the log file. Started after the
# options are read, so --help doesn't leave a log behind.
start_logging() {
  exec > >(tee -a "$LOG_FILE") 2>&1
}

# The progress gauge: whiptail reading updates from a FIFO, drawn on the
# terminal while the script's own output goes only to the log.
start_progress() {
  [[ "$PROGRESS_UI" == "1" && "$ASSUME_YES" == "1" ]] || return 0
  have_terminal && have_command whiptail || return 0

  local menu_height menu_width menu_list_height fifo
  menu_size 3
  fifo="$(mktemp -u)"
  mkfifo "$fifo" || return 0
  whiptail --title "Fedora Niri Setup" --gauge "Starting..." 12 "$menu_width" 0 \
    <"$fifo" >/dev/tty 2>/dev/null &
  PROGRESS_PID=$!
  exec {PROGRESS_FD}>"$fifo"
  rm -f "$fifo"

  exec {PROGRESS_SAVED_OUT}>&1
  exec >>"$LOG_FILE" 2>&1
  # A git password prompt would be hidden behind the gauge; fail instead.
  export GIT_TERMINAL_PROMPT=0
  progress_update "Starting."
}

# Shows the current section and $1 (the latest step) on the gauge.
progress_update() {
  [[ -n "$PROGRESS_FD" ]] || return 0
  kill -0 "$PROGRESS_PID" 2>/dev/null || {
    PROGRESS_FD=""
    return 0
  }

  local percent=0 text="$1"
  ((TOTAL_SECTIONS > 0)) && percent=$(((STEP_COUNT > 0 ? STEP_COUNT - 1 : 0) * 100 / TOTAL_SECTIONS))
  ((${#text} <= 200)) || text="${text:0:197}..."
  # In a subshell: if whiptail has died, the closed pipe's SIGPIPE ends
  # only that, not the script.
  (printf 'XXX\n%d\n[%d/%d] %s\n\n%s\n\nFull output: %s\nXXX\n' \
    "$percent" "$STEP_COUNT" "$TOTAL_SECTIONS" "$STEP_TITLE" "$text" "$LOG_FILE") 1>&"$PROGRESS_FD" 2>/dev/null || true
}

# Closes the gauge, and shows the output on the terminal (and in the log)
# again.
stop_progress() {
  [[ -n "$PROGRESS_PID" ]] || return 0

  local fd="$PROGRESS_FD" pid="$PROGRESS_PID" i
  PROGRESS_FD=""
  PROGRESS_PID=""
  [[ -z "$fd" ]] || (printf 'XXX\n100\nDone.\nXXX\n') 1>&"$fd" 2>/dev/null || true
  [[ -z "$fd" ]] || exec {fd}>&-
  # whiptail exits once its input closes; a process that inherited the
  # FIFO could keep it open, so it's stopped after a few seconds.
  for ((i = 0; i < 30; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    stty sane </dev/tty 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true

  if [[ -n "$PROGRESS_SAVED_OUT" ]]; then
    exec 1>&"$PROGRESS_SAVED_OUT" 2>&1
    exec {PROGRESS_SAVED_OUT}>&-
    PROGRESS_SAVED_OUT=""
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --configs-only) SETUP_MODE=configs ;;
      --verbose) PROGRESS_UI=0 ;;
      --no-menu) SETUP_MENU=0 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (see --help)." ;;
    esac
    shift
  done

  case "$SETUP_MODE" in
    ""|full|configs) ;;
    *) die "SETUP_MODE must be full or configs, not '$SETUP_MODE'." ;;
  esac
}

# Whether /dev/tty can be opened: the menu draws there directly, since this
# script's own output is piped into the log.
have_terminal() {
  { : </dev/tty >/dev/tty; } 2>/dev/null
}

# Runs whiptail on the terminal; its answer (what it prints on stderr) is
# printed on stdout. Fails when the user cancels or presses Esc.
whiptail_tty() {
  local answer status=0
  answer="$(mktemp)"
  whiptail "$@" 2>"$answer" >/dev/tty </dev/tty || status=$?
  cat "$answer"
  rm -f "$answer"
  return "$status"
}

# The setup menu: the mode (unless already given), then for a full install
# the feature checklist. Without the menu, the mode defaults to full.
# Cancelling exits before anything has been changed.
setup_menu() {
  if [[ "$SETUP_MENU" != "1" ]]; then
    log "Setup menu skipped; using the defaults and environment variables."
  elif ! have_terminal; then
    log "No terminal for the setup menu; using the defaults and environment variables."
  else
    if ! have_command whiptail; then
      log "Installing whiptail (newt) for the setup menu."
      run_sudo "$DNF_BIN" install -y newt || true
    fi
    if have_command whiptail; then
      [[ -n "$SETUP_MODE" ]] || choose_mode
      [[ "$SETUP_MODE" == "configs" ]] || choose_features
    else
      warn "whiptail is not available; skipping the setup menu and using the defaults and environment variables."
    fi
  fi

  SETUP_MODE="${SETUP_MODE:-full}"
  if [[ "$SETUP_MODE" == "configs" ]]; then
    TOTAL_SECTIONS=3
  fi
}

# The menu's size, fitted to the terminal (whiptail can't draw a box taller
# or wider than it). Sets menu_height, menu_width and menu_list_height for
# a list of $1 items.
menu_size() {
  local items="$1" rows=24 cols=80 size
  size="$(stty size </dev/tty 2>/dev/null || true)"
  # Some consoles report 0 0; keep the 24x80 fallback then.
  if [[ "$size" =~ ^([0-9]+)\ ([0-9]+)$ ]] && ((BASH_REMATCH[1] >= 15 && BASH_REMATCH[2] >= 50)); then
    rows="${BASH_REMATCH[1]}"
    cols="${BASH_REMATCH[2]}"
  fi
  menu_width=$((cols - 4 < 78 ? cols - 4 : 78))
  menu_height=$((rows - 2 < items + 9 ? rows - 2 : items + 9))
  menu_list_height=$((menu_height - 9 < 4 ? 4 : menu_height - 9))
}

choose_mode() {
  local menu_height menu_width menu_list_height
  menu_size 2

  if ! SETUP_MODE="$(whiptail_tty --title "Fedora Niri Setup" \
      --ok-button "Next" --cancel-button "Quit" --menu \
      "What do you want to do?" \
      "$menu_height" "$menu_width" "$menu_list_height" \
      full "Full install (packages, apps, boot, configs, ...)" \
      configs "Update configs only (niri, Alacritty, Noctalia, wallpapers)")"; then
    log "Setup cancelled from the menu; nothing was changed."
    exit 0
  fi
}

# The feature checklist, then a confirmation. Sets each feature's variable
# to 1 or 0.
choose_features() {
  local entry tag var label selection chosen skipped
  local -a items=()

  # The checklist scrolls when the features don't all fit.
  local menu_height menu_width menu_list_height
  menu_size "${#SETUP_FEATURES[@]}"
  local height="$menu_height" width="$menu_width" list_height="$menu_list_height"

  while true; do
    items=()
    for entry in "${SETUP_FEATURES[@]}"; do
      IFS='|' read -r tag var label <<<"$entry"
      items+=("$tag" "$label" "$([[ "${!var}" == "1" ]] && printf on || printf off)")
    done

    if ! selection="$(whiptail_tty --title "Fedora Niri Setup" --separate-output \
        --ok-button "Next" --cancel-button "Quit" --checklist \
        "Niri, Noctalia, the base packages and this repo's configs are always set up. Choose the rest (Space toggles, Enter continues):" \
        "$height" "$width" "$list_height" "${items[@]}")"; then
      log "Setup cancelled from the menu; nothing was changed."
      exit 0
    fi

    chosen=""
    skipped=""
    for entry in "${SETUP_FEATURES[@]}"; do
      IFS='|' read -r tag var label <<<"$entry"
      if grep -qxF -- "$tag" <<<"$selection"; then
        printf -v "$var" '%s' 1
        chosen+="${chosen:+, }$label"
      else
        printf -v "$var" '%s' 0
        skipped+="${skipped:+, }$label"
      fi
    done

    # Comma-separated, so it fits without scrolling: with --scrolltext the
    # focus starts on the text, and Enter wouldn't press "Install".
    if whiptail_tty --title "Fedora Niri Setup" --yes-button "Install" --no-button "Back" --yesno \
        "Always: Niri, Noctalia, base packages, this repo's configs.

Install: ${chosen:-nothing optional}.

Skip: ${skipped:-nothing}." "$height" "$width" >/dev/null; then
      break
    fi
  done

  local summary=""
  for entry in "${SETUP_FEATURES[@]}"; do
    IFS='|' read -r tag var label <<<"$entry"
    [[ "${!var}" == "1" ]] && summary+="${summary:+, }$tag"
  done
  log "Chosen in the setup menu: ${summary:-only the core}."
}

prepare_runtime() {
  run_as_user mkdir -p "$USER_BACKUP_ROOT"
  log "Log file: $LOG_FILE"
  log "User backups: $USER_BACKUP_ROOT"

  # Updating configs only touches the user's own files.
  [[ "$SETUP_MODE" == "full" ]] || return 0
  run_sudo install -d -m 0755 "$SYSTEM_BACKUP_ROOT"
  run_sudo -v
  log "System backups: $SYSTEM_BACKUP_ROOT"

  # Keeps sudo's timestamp fresh for the whole run, so a long step (like the
  # lsfg-vk build) doesn't end with a password prompt hidden behind the
  # progress gauge. Stops when this script does.
  (
    while kill -0 "$$" 2>/dev/null; do
      sudo -n -v 2>/dev/null || exit 0
      sleep 60
    done
  ) </dev/null >/dev/null 2>&1 &
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
  # With sudo: some system paths (the EFI System Partition) are root-only.
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
    gnome-keyring
    # Ships pam_gnome_keyring.so. Without it, greetd's PAM stack silently
    # skips unlocking the login keyring (logs "PAM adding faulty module"),
    # so anything using libsecret pops a manual "unlock keyring" prompt on
    # every login instead of auto-unlocking with the login password.
    gnome-keyring-pam
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
    # Noctalia's brightness control for external monitors (DDC/CI).
    ddcutil
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

  disable_google_chrome_repo
}

disable_google_chrome_repo() {
  [[ "$ENABLE_GOOGLE_CHROME_REPO" == "1" ]] && return 0

  local repo_file="/etc/yum.repos.d/google-chrome.repo"
  [[ -f "$repo_file" ]] || return 0
  grep -q '^enabled=1' "$repo_file" || return 0

  log "Disabling the Google Chrome repository."
  backup_system_path "$repo_file"
  run_sudo sed -i 's/^enabled=1/enabled=0/' "$repo_file"
  record_change "Disabled the Google Chrome repository."
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

  # A visible menu even with rEFInd: rEFInd boots the kernels itself, so GRUB
  # only shows up when picked as the fallback from the firmware boot menu.
  upsert_grub_default GRUB_TIMEOUT "\"$GRUB_TIMEOUT_SECONDS\""
  upsert_grub_default GRUB_TIMEOUT_STYLE "\"menu\""
  record_change "Configured GRUB timeout to $GRUB_TIMEOUT_SECONDS seconds."
  upsert_grub_default GRUB_GFXMODE "\"$GRUB_GFXMODE\""
  upsert_grub_default GRUB_TERMINAL_OUTPUT "\"gfxterm\""

  regenerate_grub_config
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

  if have_command grubby; then
    if run_sudo grubby --update-kernel=ALL --args="nowatchdog"; then
      record_change "Added the nowatchdog kernel parameter via grubby (suppresses a harmless 'watchdog did not stop' shutdown warning)."
    else
      warn "Could not add the nowatchdog kernel parameter with grubby."
    fi
  else
    warn "grubby was not found; the nowatchdog kernel parameter was not added."
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
  install_gamescope
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

  # The greeter is only needed for the login screen (ENABLE_GREETD).
  if [[ "$ENABLE_GREETD" != "1" ]]; then
    log "Installing Noctalia v5 (login screen disabled, so not Noctalia Greeter)."
    dnf_install "$NOCTALIA_PACKAGE"
    have_command noctalia || die "Noctalia package installation finished, but 'noctalia' was not found in PATH."
    record_change "Installed Noctalia v5."
    return 0
  fi

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

  # Copies everything except the previous generated block, and drops blank
  # lines at the end (printed only once something follows them), so the
  # blank line added before the block below doesn't pile up on every re-run.
  tmp="$(mktemp)"
  awk -v marker_begin="$marker_begin" -v marker_end="$marker_end" '
    $0 == marker_begin { skipping = 1; next }
    $0 == marker_end { skipping = 0; next }
    skipping { next }
    /^[[:space:]]*$/ { blank++; next }
    { while (blank > 0) { print ""; blank-- } print }
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

download_as_user() {
  local url="$1"
  local dest="$2"

  run_as_user mkdir -p "$(dirname "$dest")"
  run_as_user curl -fL "$url" -o "$dest"
}

# The rEFInd, lsfg-vk and Sunshine steps return 1 (after a warning) instead
# of stopping the script: by then the desktop is already set up, and one of
# them failing shouldn't keep the others from running. Called with `||`,
# so errexit is off inside them: every step that matters is checked.

detect_secure_boot() {
  have_command mokutil || dnf_install_best_effort mokutil

  if have_command mokutil; then
    local sb_out
    sb_out="$(run_sudo mokutil --sb-state 2>&1 || true)"
    if grep -qi 'SecureBoot enabled' <<<"$sb_out"; then
      SECURE_BOOT_STATE="enabled"
    elif grep -qi 'SecureBoot disabled' <<<"$sb_out"; then
      SECURE_BOOT_STATE="disabled"
    fi
  else
    warn "mokutil is not available; could not determine Secure Boot state."
  fi

  log "Secure Boot state: $SECURE_BOOT_STATE"
}

# Prints "NUM PATH" for each firmware boot entry labeled rEFInd, those in
# the boot order first and in that order. PATH is lowercased, since the ESP
# is case-insensitive (older installs registered \EFI\REFIND\REFIND_X64.EFI).
list_refind_boot_entries() {
  local entries num line path seen=" "
  entries="$(run_sudo efibootmgr -v 2>/dev/null || true)"
  for num in $(sed -n 's/^BootOrder: //p' <<<"$entries" | tr ',' ' ') \
    $(grep -oE '^Boot[0-9A-Fa-f]{4}\*? rEFInd' <<<"$entries" | cut -c5-8 || true); do
    [[ "$seen" != *" $num "* ]] || continue
    seen+="$num "
    line="$(grep -E "^Boot${num}\*? rEFInd" <<<"$entries" | head -1 || true)"
    [[ -n "$line" ]] || continue
    path="$(grep -oE '\\[^()]*\.[Ee][Ff][Ii]' <<<"$line" | head -1 || true)"
    printf '%s %s\n' "$num" "${path,,}"
  done
}

# Removes firmware boot entries labeled rEFInd, except the given number:
# left over from installs through shim, or duplicates. Only ever entries
# refind-install made; Fedora's and Windows' entries are never touched.
remove_refind_boot_entries() {
  local keep="${1:-}" num path
  while read -r num path; do
    [[ -n "$num" && "$num" != "$keep" ]] || continue
    if run_sudo efibootmgr -b "$num" -B >/dev/null; then
      record_change "Removed the firmware boot entry Boot$num ($path), a leftover rEFInd entry."
    else
      warn "Could not remove the leftover rEFInd firmware boot entry Boot$num ($path)."
    fi
  done < <(list_refind_boot_entries)
}

# Finds the EFI System Partition: the mount holding Fedora's shim.
resolve_esp_mount() {
  if [[ -n "$ESP_MOUNT_OVERRIDE" ]]; then
    run_sudo test -f "$ESP_MOUNT_OVERRIDE$REFIND_SHIM_LOADER_PATH" || {
      warn "ESP_MOUNT_OVERRIDE=$ESP_MOUNT_OVERRIDE does not contain $REFIND_SHIM_LOADER_PATH."
      return 1
    }
    ESP_MOUNT="$ESP_MOUNT_OVERRIDE"
  else
    local candidates=(/boot/efi /efi /boot) c
    mapfile -t -O 3 candidates < <(findmnt -rn -o TARGET --types vfat 2>/dev/null || true)
    for c in "${candidates[@]}"; do
      [[ -n "$c" ]] || continue
      if run_sudo test -f "$c$REFIND_SHIM_LOADER_PATH"; then
        ESP_MOUNT="$c"
        break
      fi
    done
  fi

  [[ -n "$ESP_MOUNT" ]] || {
    warn "Could not find $REFIND_SHIM_LOADER_PATH under /boot/efi, /efi, /boot or any mounted vfat filesystem. Set ESP_MOUNT_OVERRIDE and/or REFIND_SHIM_LOADER_PATH if your layout is unusual."
    return 1
  }
  log "EFI System Partition: $ESP_MOUNT"
}

install_refind_package() {
  if [[ "$(rpm -q --qf '%{VERSION}' refind 2>/dev/null || true)" == "$REFIND_VERSION" ]] && have_command refind-install; then
    log "rEFInd $REFIND_VERSION is already installed."
    return 0
  fi

  local rpm_path="$TARGET_HOME/.cache/fedora-niri-setup/downloads/refind-${REFIND_VERSION}-1.x86_64.rpm"
  if run_as_user test -f "$rpm_path" && file "$rpm_path" 2>/dev/null | grep -qi 'RPM'; then
    log "Using already-downloaded rEFInd $REFIND_VERSION package."
  else
    log "Downloading rEFInd $REFIND_VERSION."
    download_as_user "$REFIND_RPM_URL" "$rpm_path" || {
      warn "Could not download rEFInd from $REFIND_RPM_URL. Check REFIND_VERSION / REFIND_RPM_URL."
      return 1
    }
    # SourceForge sometimes serves an HTML page instead of the file.
    file "$rpm_path" 2>/dev/null | grep -qi 'RPM' || {
      warn "The download at $rpm_path is not an RPM (SourceForge likely served a web page instead). Download the .rpm manually and set REFIND_RPM_URL=file://<path>."
      return 1
    }
  fi

  # An upstream release asset with no signing key configured here; the GPG
  # check is skipped explicitly so dnf can't stop at a prompt.
  local args=(install --setopt=localpkg_gpgcheck=0)
  [[ "$ASSUME_YES" == "1" ]] && args+=(-y)
  run_sudo "$DNF_BIN" "${args[@]}" "$rpm_path" || {
    warn "Could not install the downloaded rEFInd package."
    return 1
  }
  have_command refind-install || {
    warn "rEFInd was installed, but refind-install was not found in PATH."
    return 1
  }
  record_change "Installed rEFInd $REFIND_VERSION."
}

run_refind_install() {
  log "Firmware boot entries before installing rEFInd:"
  run_sudo efibootmgr -v || true

  # Installs EFI/refind/refind_x64.efi plus the driver for /boot's filesystem,
  # and makes its firmware entry first in the boot order (reusing an existing
  # one). Without --yes it may ask its own questions.
  local args=()
  [[ "$ASSUME_YES" == "1" ]] && args+=(--yes)
  log "Running: refind-install ${args[*]}"
  run_sudo refind-install "${args[@]}" || {
    warn "refind-install failed. Your 'Fedora' firmware boot entry is untouched; the machine still boots normally."
    return 1
  }

  local refind_dir="$ESP_MOUNT/EFI/refind" num path
  while read -r num path; do
    if [[ "$path" == '\efi\refind\refind_x64.efi' ]]; then
      REFIND_BOOT_NUM="$num"
      break
    fi
  done < <(list_refind_boot_entries)
  [[ -n "$REFIND_BOOT_NUM" ]] && run_sudo test -f "$refind_dir/refind_x64.efi" || {
    warn "refind-install ran, but $refind_dir/refind_x64.efi or its firmware boot entry is missing."
    return 1
  }
  if [[ "$(run_sudo efibootmgr | sed -n 's/^BootOrder: //p' | cut -d, -f1)" != "$REFIND_BOOT_NUM" ]]; then
    warn "rEFInd's entry Boot$REFIND_BOOT_NUM isn't first in the firmware boot order; pick it in your firmware settings, or run: sudo efibootmgr -o $REFIND_BOOT_NUM,<the others>"
  fi
  remove_refind_boot_entries "$REFIND_BOOT_NUM"

  # Installs through shim (by an earlier version of this script) left shim,
  # MokManager and a renamed rEFInd (grubx64.efi) in rEFInd's own directory.
  # Nothing boots them any more; EFI/fedora's copies are separate.
  for path in shimx64.efi mmx64.efi grubx64.efi; do
    if run_sudo test -f "$refind_dir/$path"; then
      backup_system_path "$refind_dir/$path"
      run_sudo rm -f "$refind_dir/$path" && record_change "Removed the leftover $refind_dir/$path."
    fi
  done

  log "Firmware boot entries after installing rEFInd:"
  run_sudo efibootmgr -v || true
  record_change "Registered rEFInd as firmware boot entry Boot$REFIND_BOOT_NUM, first in the boot order (the Fedora entry is left in place)."
}

find_refind_conf() {
  if [[ -n "$REFIND_CONF_PATH" ]]; then
    if run_sudo test -f "$REFIND_CONF_PATH"; then
      printf '%s\n' "$REFIND_CONF_PATH"
      return 0
    fi
    warn "REFIND_CONF_PATH=$REFIND_CONF_PATH does not exist; searching for refind.conf instead."
  fi

  local hit
  hit="$(run_sudo find "$ESP_MOUNT" -maxdepth 4 -iname 'refind.conf' 2>/dev/null | head -1)"
  [[ -n "$hit" ]] || return 1
  printf '%s\n' "$hit"
}

install_refind_theme() {
  local refind_conf="$1"

  log "Fetching rEFInd theme from $REFIND_THEME_REPO."
  clone_or_update_git_repo "$REFIND_THEME_REPO" "$REFIND_THEME_DIR"
  [[ -f "$REFIND_THEME_DIR/theme.conf" ]] || {
    warn "$REFIND_THEME_DIR has no theme.conf, so it's not a rEFInd theme; skipping the theme."
    return 0
  }

  local theme_dest tmp_theme
  theme_dest="$(dirname "$refind_conf")/themes/$REFIND_THEME_NAME"

  backup_system_path "$theme_dest"
  run_sudo rm -rf "$theme_dest"
  run_sudo mkdir -p "$theme_dest"
  tmp_theme="$(mktemp -d)"
  cp -r "$REFIND_THEME_DIR/." "$tmp_theme/"
  rm -rf "$tmp_theme/.git"
  # -r, not -a: the ESP is vfat, which has no Unix ownership, so cp -a fails
  # trying to chown there even as root.
  run_sudo cp -r "$tmp_theme/." "$theme_dest/"
  rm -rf "$tmp_theme"
  run_sudo test -f "$theme_dest/theme.conf" || {
    warn "Copying the rEFInd theme to $theme_dest failed (no theme.conf there afterwards)."
    return 1
  }
  record_change "Installed rEFInd theme '$REFIND_THEME_NAME' to $theme_dest."

  if run_sudo grep -qE "^include[[:space:]]+themes/${REFIND_THEME_NAME}/theme\.conf[[:space:]]*\$" "$refind_conf"; then
    log "Theme already included in $refind_conf."
    return 0
  fi

  local tmp
  backup_system_path "$refind_conf"
  tmp="$(mktemp)"
  run_sudo cat "$refind_conf" >"$tmp"
  printf '\ninclude themes/%s/theme.conf\n' "$REFIND_THEME_NAME" >>"$tmp"
  run_sudo install -m 0644 "$tmp" "$refind_conf"
  rm -f "$tmp"
  record_change "Enabled rEFInd theme '$REFIND_THEME_NAME' in $refind_conf."
}

configure_refind_conf() {
  local refind_conf="$1"
  local tmp resolution_line="" dont_scan_line=""

  backup_system_path "$refind_conf"

  # Copies everything except the previous generated block, and drops blank
  # lines at the end (printed only once something follows them), so the
  # blank line added before the block below doesn't pile up on every re-run.
  tmp="$(mktemp)"
  run_sudo awk -v marker_begin="$REFIND_MARKER_BEGIN" -v marker_end="$REFIND_MARKER_END" '
    $0 == marker_begin { skipping = 1; next }
    $0 == marker_end { skipping = 0; next }
    skipping { next }
    /^[[:space:]]*$/ { blank++; next }
    { while (blank > 0) { print ""; blank-- } print }
  ' "$refind_conf" >"$tmp"

  [[ ! -s "$tmp" ]] || printf '\n' >>"$tmp"

  if [[ -n "$REFIND_RESOLUTION_WIDTH" && -n "$REFIND_RESOLUTION_HEIGHT" ]]; then
    resolution_line="resolution $REFIND_RESOLUTION_WIDTH $REFIND_RESOLUTION_HEIGHT"
  fi
  [[ -z "$REFIND_DONT_SCAN_DIRS" ]] || dont_scan_line="dont_scan_dirs $REFIND_DONT_SCAN_DIRS"

  # No manual entry: the scan finds the kernels in /boot, folded into one
  # menu entry that boots the newest (older ones under F2/Tab/Insert).
  # use_graphics_for starts them in graphics mode, without the text screen
  # rEFInd otherwise shows ("Starting vmlinuz-...") before Plymouth.
  cat >>"$tmp" <<EOF
$REFIND_MARKER_BEGIN
timeout $REFIND_TIMEOUT_SECONDS
scanfor $REFIND_SCANFOR
$dont_scan_line
scan_all_linux_kernels true
fold_linux_kernels true
use_graphics_for linux,windows
$resolution_line
$REFIND_MARKER_END
EOF

  run_sudo install -m 0644 "$tmp" "$refind_conf" || {
    rm -f "$tmp"
    warn "Could not write $refind_conf."
    return 1
  }
  rm -f "$tmp"
  record_change "Configured rEFInd to boot the kernels in /boot directly, with a ${REFIND_TIMEOUT_SECONDS}s timeout, in $refind_conf."
}

# rEFInd doesn't read Fedora's boot entries (/boot/loader/entries), so it
# gets the kernel options from /boot/refind_linux.conf, next to the kernels.
# They're taken from GRUB's default entry, so options set with grubby
# (Plymouth, nowatchdog, ...) apply to both.
write_refind_linux_conf() {
  local info root args="" options
  if have_command grubby && info="$(run_sudo grubby --info=DEFAULT 2>/dev/null)"; then
    root="$(sed -n 's/^root="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' <<<"$info" | head -1)"
    args="$(sed -n 's/^args="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' <<<"$info" | head -1)"
    [[ -z "$root" ]] || args="root=$root $args"
  fi
  if [[ "$args" != *root=* ]]; then
    log "Could not read GRUB's default kernel options; using the running kernel's."
    args="$(tr ' ' '\n' </proc/cmdline | grep -vE '^(BOOT_IMAGE|initrd)=' | tr '\n' ' ')"
  fi
  # Drop BLS variables like $tuned_params, which only GRUB expands, and
  # extra spaces.
  options="$(tr ' ' '\n' <<<"$args" | grep -v '^\$' | grep . | tr '\n' ' ')"
  options="${options% }"
  [[ "$options" == *root=* ]] || {
    warn "Could not work out the kernel options (no root=); /boot/refind_linux.conf was not written."
    return 1
  }

  local plain
  plain="$(tr ' ' '\n' <<<"$options" | grep -vxE 'rhgb|quiet|splash' | tr '\n' ' ')"
  write_system_file /boot/refind_linux.conf 0644 <<EOF
# Generated by fedora-niri-setup.sh from GRUB's default entry (grubby
# --info=DEFAULT), and rewritten on every run. Kernel options for rEFInd,
# which boots the kernels in /boot directly. rEFInd adds initrd= itself.
"Boot with standard options"  "$options"
"Boot with text output"       "${plain% }"
"Boot to single-user mode"    "${plain% } single"
EOF
  run_sudo grep -qF "\"$options\"" /boot/refind_linux.conf || {
    warn "Could not write /boot/refind_linux.conf."
    return 1
  }
  record_change "Wrote rEFInd's kernel options to /boot/refind_linux.conf: $options"
}

# Gives every kernel in /boot the theme's Fedora icon, now and (through a
# kernel-install hook) after each kernel update.
install_refind_kernel_icons() {
  local refind_conf="$1" icon
  icon="$(dirname "$refind_conf")/$REFIND_KERNEL_ICON"
  run_sudo test -f "$icon" || {
    warn "Theme icon $icon was not found; rEFInd will show its default Linux icon for the kernels."
    return 0
  }

  write_system_file "$REFIND_ICON_HOOK" 0755 <<EOF
#!/bin/sh
# Installed by fedora-niri-setup.sh. rEFInd shows a kernel with the icon
# named after it (vmlinuz-<version>.png), so give every kernel in /boot the
# Fedora icon, and drop icons whose kernel is gone. Runs on every
# kernel-install add/remove; the arguments aren't needed.
icon='$icon'
[ -f "\$icon" ] || exit 0
for kernel in /boot/vmlinuz-*; do
  case "\$kernel" in *.png) continue ;; esac
  [ -f "\$kernel" ] || continue
  cmp -s "\$icon" "\$kernel.png" || cp "\$icon" "\$kernel.png"
done
for png in /boot/vmlinuz-*.png; do
  [ -f "\$png" ] || continue
  [ -f "\${png%.png}" ] || rm -f "\$png"
done
exit 0
EOF
  if run_sudo "$REFIND_ICON_HOOK"; then
    record_change "Gave the kernels in /boot rEFInd's Fedora icon, kept up to date by $REFIND_ICON_HOOK."
  else
    warn "Could not add rEFInd icons for the kernels in /boot."
  fi
}

install_refind() {
  [[ -d /sys/firmware/efi ]] || {
    warn "This machine is not booted in UEFI mode; rEFInd needs UEFI, so it was skipped."
    return 0
  }

  detect_secure_boot
  if [[ "$SECURE_BOOT_STATE" == "enabled" ]]; then
    warn "Secure Boot is on, so rEFInd was skipped and GRUB stays the boot menu: this rEFInd is unsigned, and Fedora's shim can't load rEFInd 0.14.2 anyway (github.com/rhboot/shim/issues/803). To use rEFInd, turn Secure Boot off in the firmware settings and re-run the script."
    # Entries from an earlier install can't boot with Secure Boot on.
    remove_refind_boot_entries
    return 0
  fi

  # rEFInd's ext4 driver reads the kernels from /boot. On btrfs (no separate
  # /boot) they sit in a subvolume, which rEFInd doesn't find by itself.
  # Only the first line: /boot can be mounted twice, stacked (Fedora does
  # this), and findmnt then lists it twice.
  local boot_target="" boot_fstype=""
  read -r boot_target boot_fstype < <(findmnt -n -o TARGET,FSTYPE --target /boot 2>/dev/null || true)
  [[ "$boot_target" == /boot && "$boot_fstype" == ext[234] ]] || {
    if [[ "$boot_target" == /boot ]]; then
      warn "rEFInd needs /boot on its own ext4 partition (Fedora's default layout), but /boot is $boot_fstype; rEFInd was skipped and GRUB stays the boot menu."
    else
      warn "rEFInd needs /boot on its own ext4 partition (Fedora's default layout), but /boot is part of ${boot_target:-another filesystem}; rEFInd was skipped and GRUB stays the boot menu."
    fi
    return 1
  }

  resolve_esp_mount || return 1
  install_refind_package || return 1
  run_refind_install || return 1

  local refind_conf
  refind_conf="$(find_refind_conf || true)"
  [[ -n "$refind_conf" ]] || {
    warn "refind-install succeeded, but no refind.conf was found under $ESP_MOUNT."
    return 1
  }
  install_refind_theme "$refind_conf" || return 1
  configure_refind_conf "$refind_conf" || return 1
  write_refind_linux_conf || return 1
  install_refind_kernel_icons "$refind_conf"
  REFIND_INSTALLED=1
}

install_lsfg_vk_dependencies() {
  log "Installing lsfg-vk build dependencies."
  dnf_install \
    git curl \
    llvm clang clang-tools-extra \
    cmake ninja-build pkgconf-pkg-config \
    vulkan-loader-devel \
    mesa-libGL-devel \
    qt6-qtbase-devel \
    qt6-qttools-devel \
    qt6-qtdeclarative-devel || {
    warn "Could not install the lsfg-vk build dependencies."
    return 1
  }

  [[ "$INSTALL_VULKAN_TOOLS" == "1" ]] || return 0
  package_installed vulkan-tools || dnf_install_optional vulkan-tools || true
}

clone_or_update_lsfg_vk() {
  local dir="$LSFG_VK_BUILD_DIR"

  if [[ -d "$dir/.git" ]]; then
    log "Updating the lsfg-vk checkout at $dir."
    run_as_user git -C "$dir" fetch --tags origin || {
      warn "Could not fetch lsfg-vk updates."
      return 1
    }
    if [[ -z "$LSFG_VK_REPO_TAG" ]]; then
      { run_as_user git -C "$dir" checkout main || run_as_user git -C "$dir" checkout master; } &&
        run_as_user git -C "$dir" pull --ff-only || {
        warn "Could not update lsfg-vk to the latest source."
        return 1
      }
    fi
  else
    log "Cloning lsfg-vk from $LSFG_VK_REPO_URL."
    run_as_user mkdir -p "$(dirname "$dir")"
    run_as_user git clone "$LSFG_VK_REPO_URL" "$dir" || {
      warn "Could not clone lsfg-vk."
      return 1
    }
  fi

  if [[ -n "$LSFG_VK_REPO_TAG" ]]; then
    run_as_user git -C "$dir" checkout "tags/$LSFG_VK_REPO_TAG" || {
      warn "Could not check out lsfg-vk tag $LSFG_VK_REPO_TAG."
      return 1
    }
  fi
}

# The layer's manifest names liblsfg-vk-layer.so by bare filename, and Fedora
# doesn't search /usr/local/lib64 by default, so the Vulkan loader silently
# fails to load it for every app. Register the install's lib dir if needed.
register_lsfg_vk_library_path() {
  local lib_path lib_dir
  lib_path="$(find "$LSFG_VK_INSTALL_PREFIX" -name 'liblsfg-vk-layer.so' 2>/dev/null | head -n1)"
  if [[ -z "$lib_path" ]]; then
    warn "Could not find liblsfg-vk-layer.so under $LSFG_VK_INSTALL_PREFIX to check the library search path."
    return 0
  fi
  lib_dir="$(dirname "$lib_path")"

  if ldconfig -p | grep -q 'liblsfg-vk-layer\.so '; then
    log "liblsfg-vk-layer.so is already on the library search path."
    return 0
  fi

  log "Registering $lib_dir with ldconfig so the Vulkan loader can find the lsfg-vk layer."
  printf '%s\n' "$lib_dir" | write_system_file /etc/ld.so.conf.d/lsfg-vk.conf || {
    warn "Could not write /etc/ld.so.conf.d/lsfg-vk.conf."
    return 1
  }
  run_sudo ldconfig || {
    warn "ldconfig failed after registering $lib_dir."
    return 1
  }
  record_change "Registered $lib_dir with ldconfig so the Vulkan loader can find liblsfg-vk-layer.so."
}

# File checks and lsfg-vk-cli's healthcheck don't catch a layer the loader
# can't open, so run vkcube briefly and check the loader inserted it.
verify_lsfg_vk_layer_loads() {
  have_command vkcube || {
    warn "vkcube not found; skipped checking that the lsfg-vk layer loads."
    return 0
  }
  [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] || {
    log "No graphical session; skipped checking that the lsfg-vk layer loads with vkcube."
    return 0
  }

  local out
  out="$(mktemp)"
  timeout 3 env VK_LOADER_DEBUG=layer vkcube >"$out" 2>&1 || true
  if grep -q 'Insert instance layer "VK_LAYER_LSFGVK_frame_generation"' "$out"; then
    log "Verified with vkcube that the Vulkan loader loads the lsfg-vk layer."
  else
    warn "vkcube did not load the lsfg-vk layer. Investigate with: VK_LOADER_DEBUG=layer vkcube 2>&1 | grep -i lsfgvk"
  fi
  rm -f "$out"
}

install_lsfg_vk() {
  install_lsfg_vk_dependencies || return 1
  clone_or_update_lsfg_vk || return 1

  local lto_flag=OFF ui_flag=OFF
  [[ "$LSFG_VK_ENABLE_LTO" == "1" ]] && lto_flag=ON
  [[ "$LSFG_VK_BUILD_UI" == "1" ]] && ui_flag=ON

  log "Configuring the lsfg-vk build (prefix: $LSFG_VK_INSTALL_PREFIX, type: $LSFG_VK_BUILD_TYPE, UI: $ui_flag)."
  run_as_user cmake -S "$LSFG_VK_BUILD_DIR" -B "$LSFG_VK_BUILD_DIR/build" -G Ninja \
    -DCMAKE_BUILD_TYPE="$LSFG_VK_BUILD_TYPE" \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION="$lto_flag" \
    -DCMAKE_INSTALL_PREFIX="$LSFG_VK_INSTALL_PREFIX" \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DLSFGVK_BUILD_UI="$ui_flag" || {
    warn "lsfg-vk's CMake configuration failed."
    return 1
  }

  log "Building lsfg-vk (this can take a while)."
  run_as_user cmake --build "$LSFG_VK_BUILD_DIR/build" || {
    warn "The lsfg-vk build failed."
    return 1
  }

  run_sudo cmake --install "$LSFG_VK_BUILD_DIR/build" || {
    warn "Installing lsfg-vk to $LSFG_VK_INSTALL_PREFIX failed."
    return 1
  }
  record_change "Built and installed lsfg-vk to $LSFG_VK_INSTALL_PREFIX."
  LSFG_VK_INSTALLED=1

  register_lsfg_vk_library_path || return 1
  verify_lsfg_vk_layer_loads

  if have_command lsfg-vk-cli; then
    log "Running the lsfg-vk-cli healthcheck."
    run_as_user lsfg-vk-cli healthcheck || warn "The lsfg-vk-cli healthcheck reported issues; see its output above."
  else
    warn "lsfg-vk-cli was not found on PATH after installing; skipped its healthcheck."
  fi
}

# Sets output_name (the connector Sunshine captures) in sunshine.conf.
configure_sunshine_capture_output() {
  local config_file="$SUNSHINE_CONFIG_DIR/sunshine.conf"
  local tmp

  if [[ -f "$config_file" ]] && grep -qE "^output_name *= *$SUNSHINE_CAPTURE_OUTPUT\$" "$config_file"; then
    log "Sunshine's capture output is already $SUNSHINE_CAPTURE_OUTPUT."
    return 0
  fi

  tmp="$(mktemp)"
  if [[ -f "$config_file" ]]; then
    grep -v '^output_name' "$config_file" >"$tmp" || true
  fi
  printf 'output_name = %s\n' "$SUNSHINE_CAPTURE_OUTPUT" >>"$tmp"
  write_user_file "$config_file" 0644 <"$tmp"
  rm -f "$tmp"
  record_change "Set Sunshine's capture output (output_name) to $SUNSHINE_CAPTURE_OUTPUT in $config_file."
}

# Sunshine's user service as installed: app-dev.lizardbyte.app.Sunshine in
# current packages, sunshine in older ones. systemd won't enable a unit by
# an alias name, and current packages only keep "sunshine" as an alias.
sunshine_unit() {
  local unit dir
  for unit in app-dev.lizardbyte.app.Sunshine.service sunshine.service; do
    for dir in /usr/lib/systemd/user /usr/local/lib/systemd/user /etc/systemd/user; do
      if [[ -f "$dir/$unit" && ! -L "$dir/$unit" ]]; then
        printf '%s' "$unit"
        return 0
      fi
    done
  done
  return 1
}

install_sunshine() {
  enable_copr_repo "$SUNSHINE_COPR" "Sunshine" || return 1
  dnf_install_optional Sunshine || return 1
  record_change "Installed Sunshine from COPR $SUNSHINE_COPR."
  SUNSHINE_INSTALLED=1

  configure_sunshine_capture_output

  if [[ "$ENABLE_SUNSHINE_AUTOSTART" != "1" ]]; then
    log "Sunshine autostart is disabled."
    return 0
  fi
  local unit
  unit="$(sunshine_unit || true)"
  [[ -n "$unit" ]] || {
    warn "Could not find Sunshine's systemd user service; autostart was not set up."
    return 0
  }
  if set_systemd_user_service "$unit"; then
    record_change "Enabled the Sunshine user service ($unit) to start on login."
  fi
}

install_extras() {
  if [[ "$INSTALL_REFIND" == "1" ]]; then
    log "Setting up the rEFInd boot menu."
    install_refind || warn "rEFInd setup stopped early (see above); re-run the script once it's fixed. Your 'Fedora' firmware boot entry is untouched."
  else
    log "rEFInd setup is disabled."
  fi

  if [[ "$INSTALL_LSFG_VK" == "1" ]]; then
    log "Building lsfg-vk frame generation."
    install_lsfg_vk || warn "lsfg-vk was not installed (see above); re-run the script once it's fixed."
  else
    log "lsfg-vk installation is disabled."
  fi

  if [[ "$INSTALL_SUNSHINE" == "1" ]]; then
    log "Installing the Sunshine streaming host."
    install_sunshine || warn "Sunshine was not installed (see above); re-run the script once it's fixed."
  else
    log "Sunshine installation is disabled."
  fi
}

# The manual steps left after rEFInd, lsfg-vk and Sunshine, which can't be
# scripted.
print_next_steps() {
  ((REFIND_INSTALLED || LSFG_VK_INSTALLED || SUNSHINE_INSTALLED)) || return 0

  printf '\n  %sNext steps:%s\n' "$COLOR_GREEN" "$COLOR_RESET"

  if ((SUNSHINE_INSTALLED)); then
    printf '\n  Sunshine:\n'
    printf '  1. Open https://localhost:47990 and create the Sunshine admin login.\n'
    printf '     Sunshine accepts no streams until that is done.\n'
    printf '  2. Log in to Steam and install games, then add them to Sunshine with:\n'
    printf '     bash %s/steam-sunshine-sync.sh --select\n' "$CONFIG_SOURCE_DIR"
  fi

  if ((LSFG_VK_INSTALLED)); then
    printf '\n  lsfg-vk:\n'
    printf '  1. Buy and install Lossless Scaling on Steam, and switch it to the\n'
    printf '     "lsfg-vk" beta branch (right-click > Properties > Betas). If your\n'
    printf '     Steam library is in an unusual place, set "dll" under [global] in\n'
    printf '     ~/.config/lsfg-vk/conf.toml.\n'
    printf '  2. Run lsfg-vk-ui to create a profile, or launch a game with\n'
    printf '     LSFGVK_PROFILE=<name>.\n'
    printf '  3. Check the layer loads with vkcube (DISABLE_LSFGVK=1 vkcube to\n'
    printf '     compare). Pacing mode needs Vsync on. Docs: https://lsfg-vk.dev/docs/getting-started/\n'
  fi

  if ((REFIND_INSTALLED)); then
    printf '\n  rEFInd (boots the kernels in /boot directly; keep Secure Boot off):\n'
    printf '  - Older kernels: press F2/Tab on the Fedora entry.\n'
    printf '  - Kernel options are in /boot/refind_linux.conf, copied from GRUB'\''s\n'
    printf '    default entry. After changing them with grubby, re-run this script.\n'
    printf '  - GRUB is the fallback: if rEFInd ever fails, pick "Fedora" in the\n'
    printf '    firmware boot menu (F12/F2 at POST).\n'
    printf '  - To undo: sudo efibootmgr -b %s -B   (removes the rEFInd entry)\n' "$REFIND_BOOT_NUM"
  fi
}

print_summary() {
  local item

  stop_progress

  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  Setup complete%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '\n'
  printf '  Log:            %s\n' "$LOG_FILE"
  printf '  User backups:   %s\n' "$USER_BACKUP_ROOT"
  [[ "$SETUP_MODE" != "full" ]] || printf '  System backups: %s\n' "$SYSTEM_BACKUP_ROOT"

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

  print_next_steps

  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n' "$COLOR_GREEN" "$COLOR_RESET"
}

# Configs only: this repo's configs and wallpapers, and the Noctalia
# wallpaper settings (its config directory is replaced with the repo's).
update_configs() {
  section "Repo configs"
  have_command git || die "git is needed to fetch the config repo; install it, or run the full install."
  clone_or_update_config_repo
  verify_config_source
  install_user_configs
  install_wallpapers
  configure_noctalia_settings

  section "Summary"
  print_summary
}

main() {
  parse_args "$@"
  start_logging
  print_banner
  require_fedora
  setup_menu
  section "Fedora Niri setup"
  log "Mode: $([[ "$SETUP_MODE" == "configs" ]] && printf 'update configs only' || printf 'full install')"
  resolve_target_user
  prepare_runtime
  start_progress

  if [[ "$SETUP_MODE" == "configs" ]]; then
    update_configs
    return 0
  fi

  section "Base packages"
  install_fedora_packages
  install_flatpak

  section "Default apps"
  install_default_apps

  section "Boot visuals"
  configure_plymouth_and_grub
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

  section "Boot menu, frame generation and streaming"
  install_extras

  section "Summary"
  print_summary
}

main "$@"
