#!/usr/bin/env bash
set -Eeuo pipefail

# Installs Sunshine (LizardByte's self-hosted Moonlight streaming host)
# from each distro's beta channel, and enables it to start on login.
#
# Fully standalone -- run this by itself, once, on a machine that already
# has its desktop set up. Not called by fedora-niri-setup.sh or
# arch-niri-setup.sh, and does not require either to have been run first.
#
# Installs the native package rather than the Flatpak build: Flatpak's
# Sunshine sandbox does not support KMS screen capture, which this repo's
# bare-Wayland/niri sessions need for streaming to actually work.
#   Fedora: LizardByte's own COPR, beta channel.
#   Arch:   the AUR's nightly/beta package (sunshine-git), via an AUR helper
#           (paru by default, set AUR_HELPER=yay to use that instead) --
#           bootstrapped from the AUR itself if not already installed.

SUNSHINE_COPR="${SUNSHINE_COPR:-lizardbyte/beta}"
SUNSHINE_AUR_PACKAGE="${SUNSHINE_AUR_PACKAGE:-sunshine-git}"
AUR_HELPER="${AUR_HELPER:-paru}"
ASSUME_YES="${ASSUME_YES:-1}"
ENABLE_SUNSHINE_AUTOSTART="${ENABLE_SUNSHINE_AUTOSTART:-1}"

declare -a CHANGES=()
declare -a WARNINGS=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_GREEN=$'\033[1;32m'
  COLOR_YELLOW=$'\033[1;33m'
  COLOR_RED=$'\033[1;31m'
  COLOR_DIM=$'\033[2m'
else
  COLOR_RESET=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_DIM=""
fi

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

detect_distro() {
  [[ -f /etc/os-release ]] || die "Cannot detect distro: /etc/os-release not found."

  local id id_like
  id="$(grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"')"
  id_like="$(grep -oP '^ID_LIKE=\K.*' /etc/os-release 2>/dev/null | tr -d '"')"

  case "$id $id_like" in
    *fedora*) printf 'fedora' ;;
    *arch*) printf 'arch' ;;
    *) die "Unsupported distro (ID=$id ID_LIKE=$id_like). This script supports Fedora and Arch only." ;;
  esac
}

install_sunshine_fedora() {
  have_command dnf || die "dnf was not found."

  sudo dnf install -y dnf-plugins-core || warn "Could not ensure dnf-plugins-core is installed; 'dnf copr' may not work."

  log "Enabling LizardByte COPR ($SUNSHINE_COPR)."
  sudo dnf copr enable -y "$SUNSHINE_COPR" || die "Could not enable COPR $SUNSHINE_COPR."
  record_change "Enabled COPR $SUNSHINE_COPR."

  log "Installing Sunshine."
  sudo dnf install -y Sunshine || die "Could not install Sunshine."
  record_change "Installed Sunshine from COPR $SUNSHINE_COPR."
}

ensure_aur_helper() {
  have_command "$AUR_HELPER" && return 0

  log "$AUR_HELPER was not found; bootstrapping it from the AUR."
  have_command sudo || die "sudo was not found; cannot bootstrap $AUR_HELPER."
  have_command pacman || die "pacman was not found; cannot bootstrap $AUR_HELPER."
  have_command git || sudo pacman -S --needed --noconfirm git || die "Could not install git (required to bootstrap $AUR_HELPER)."
  sudo pacman -S --needed --noconfirm base-devel || die "Could not install base-devel (required to build $AUR_HELPER)."

  local build_dir
  build_dir="$(mktemp -d)"
  git clone "https://aur.archlinux.org/${AUR_HELPER}.git" "$build_dir" || die "Could not clone $AUR_HELPER from the AUR."

  (cd "$build_dir" && makepkg -si --noconfirm --needed) || die "Could not build/install $AUR_HELPER. Check the output above."
  rm -rf "$build_dir"

  have_command "$AUR_HELPER" || die "$AUR_HELPER installation finished, but it was not found in PATH."
  record_change "Bootstrapped the $AUR_HELPER AUR helper."
}

install_sunshine_arch() {
  ensure_aur_helper

  log "Installing $SUNSHINE_AUR_PACKAGE from the AUR via $AUR_HELPER (source build -- this can take a while)."
  local args=(-S --needed)
  [[ "$ASSUME_YES" == "1" ]] && args+=(--noconfirm)
  "$AUR_HELPER" "${args[@]}" "$SUNSHINE_AUR_PACKAGE" || die "Could not install $SUNSHINE_AUR_PACKAGE."
  record_change "Installed $SUNSHINE_AUR_PACKAGE from the AUR."
}

configure_autostart() {
  [[ "$ENABLE_SUNSHINE_AUTOSTART" == "1" ]] || {
    log "Sunshine autostart is disabled."
    return 0
  }

  have_command systemctl || {
    warn "systemctl was not found; skipping autostart setup."
    return 0
  }

  local uid
  uid="$(id -u)"
  if [[ -d "/run/user/$uid" ]]; then
    if systemctl --user enable --now sunshine; then
      record_change "Enabled and started the sunshine user service."
      return 0
    fi
    warn "Could not enable/start the sunshine user service now."
  else
    if systemctl --user enable sunshine; then
      warn "Enabled the sunshine user service for autostart, but could not start it now because /run/user/$uid does not exist (no active login session)."
      return 0
    fi
    warn "Could not enable the sunshine user service."
  fi
}

print_summary() {
  printf '\n%s  ────────────────────────────────────────────%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  Sunshine install complete%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  ────────────────────────────────────────────%s\n' "$COLOR_GREEN" "$COLOR_RESET"

  if ((${#CHANGES[@]})); then
    printf '\n  %sChanges:%s\n' "$COLOR_GREEN" "$COLOR_RESET"
    local item
    for item in "${CHANGES[@]}"; do
      printf '  %s✓%s  %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$item"
    done
  fi

  if ((${#WARNINGS[@]})); then
    printf '\n  %sWarnings:%s\n' "$COLOR_YELLOW" "$COLOR_RESET"
    local item
    for item in "${WARNINGS[@]}"; do
      printf '  %s⚠%s  %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$item"
    done
  fi

  printf '\n  %sOne manual step remains and cannot be scripted:%s\n' "$COLOR_DIM" "$COLOR_RESET"
  printf '  Open https://localhost:47990 in a browser and set the initial Sunshine\n'
  printf '  admin username/password -- Sunshine will not accept streaming\n'
  printf '  connections (or API/web-UI changes) until that one-time setup is done.\n'
  printf '\n  Once Sunshine is set up, use steam-sunshine-sync.sh (in this repo) to\n'
  printf '  sync your Steam library into it.\n'
  printf '\n'
}

main() {
  local distro
  distro="$(detect_distro)"
  log "Detected distro: $distro."

  case "$distro" in
    fedora) install_sunshine_fedora ;;
    arch) install_sunshine_arch ;;
  esac

  configure_autostart
  print_summary
}

main "$@"
