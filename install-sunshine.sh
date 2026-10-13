#!/usr/bin/env bash
set -Eeuo pipefail

# Installs Sunshine (LizardByte's self-hosted Moonlight streaming host) on
# Fedora from LizardByte's own COPR (stable channel), and enables it to
# start on login.
#
# Run by fedora-niri-setup.sh at the end of its setup (INSTALL_SUNSHINE=1,
# the default), but also standalone: run it by itself on a machine that
# already has its desktop set up. Safe to re-run.
#
# Installs the native package rather than the Flatpak build: Flatpak's
# Sunshine sandbox does not support KMS screen capture, which this repo's
# bare-Wayland/niri sessions need for streaming to actually work.
#
# Also sets sunshine.conf's capture output (output_name) to DP-2 by default
# -- override with SUNSHINE_CAPTURE_OUTPUT if that's not the right connector
# on this machine (find names with: niri msg outputs).

SUNSHINE_COPR="${SUNSHINE_COPR:-lizardbyte/stable}"
ENABLE_SUNSHINE_AUTOSTART="${ENABLE_SUNSHINE_AUTOSTART:-1}"
SUNSHINE_CAPTURE_OUTPUT="${SUNSHINE_CAPTURE_OUTPUT:-DP-2}"
SUNSHINE_CONFIG_DIR="${SUNSHINE_CONFIG_DIR:-$HOME/.config/sunshine}"
SUNSHINE_CONFIG_FILE="${SUNSHINE_CONFIG_FILE:-$SUNSHINE_CONFIG_DIR/sunshine.conf}"

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

require_fedora() {
  [[ -f /etc/os-release ]] || die "Cannot detect distro: /etc/os-release not found."
  grep -qi '^ID=fedora' /etc/os-release || die "This script only supports Fedora."
  have_command dnf || die "dnf was not found."
}

install_sunshine() {
  sudo dnf install -y dnf-plugins-core || warn "Could not ensure dnf-plugins-core is installed; 'dnf copr' may not work."

  log "Enabling LizardByte COPR ($SUNSHINE_COPR)."
  sudo dnf copr enable -y "$SUNSHINE_COPR" || die "Could not enable COPR $SUNSHINE_COPR."
  record_change "Enabled COPR $SUNSHINE_COPR."

  log "Installing Sunshine."
  sudo dnf install -y Sunshine || die "Could not install Sunshine."
  record_change "Installed Sunshine from COPR $SUNSHINE_COPR."
}

# Deletes all but the newest $2 "$1.bak.<timestamp>" backups. The
# timestamps sort by name, oldest first.
prune_backups() {
  local file="$1" keep="$2"
  local -a backups=()
  mapfile -t backups < <(compgen -G "$file.bak.*" | sort)
  ((${#backups[@]} > keep)) || return 0
  rm -f -- "${backups[@]:0:${#backups[@]}-keep}"
}

configure_capture_output() {
  mkdir -p "$SUNSHINE_CONFIG_DIR"

  if [[ -f "$SUNSHINE_CONFIG_FILE" ]] && grep -q '^output_name' "$SUNSHINE_CONFIG_FILE"; then
    if grep -qE "^output_name *= *$SUNSHINE_CAPTURE_OUTPUT\$" "$SUNSHINE_CONFIG_FILE"; then
      log "Capture output already set to $SUNSHINE_CAPTURE_OUTPUT in $SUNSHINE_CONFIG_FILE."
      return 0
    fi
    cp -p "$SUNSHINE_CONFIG_FILE" "$SUNSHINE_CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    prune_backups "$SUNSHINE_CONFIG_FILE" 5
    sed -i "s/^output_name.*/output_name = $SUNSHINE_CAPTURE_OUTPUT/" "$SUNSHINE_CONFIG_FILE"
  else
    printf 'output_name = %s\n' "$SUNSHINE_CAPTURE_OUTPUT" >> "$SUNSHINE_CONFIG_FILE"
  fi
  record_change "Set capture output (output_name) to $SUNSHINE_CAPTURE_OUTPUT in $SUNSHINE_CONFIG_FILE."
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

configure_autostart() {
  [[ "$ENABLE_SUNSHINE_AUTOSTART" == "1" ]] || {
    log "Sunshine autostart is disabled."
    return 0
  }

  have_command systemctl || {
    warn "systemctl was not found; skipping autostart setup."
    return 0
  }

  local unit
  unit="$(sunshine_unit || true)"
  [[ -n "$unit" ]] || {
    warn "Could not find Sunshine's systemd user service; autostart was not set up."
    return 0
  }

  local uid
  uid="$(id -u)"
  if [[ -d "/run/user/$uid" ]]; then
    if systemctl --user enable --now "$unit"; then
      record_change "Enabled and started the Sunshine user service ($unit)."
      return 0
    fi
    warn "Could not enable/start the Sunshine user service ($unit) now."
  else
    if systemctl --user enable "$unit"; then
      warn "Enabled the Sunshine user service ($unit) for autostart, but could not start it now because /run/user/$uid does not exist (no active login session)."
      return 0
    fi
    warn "Could not enable the Sunshine user service ($unit)."
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
  require_fedora
  install_sunshine
  configure_capture_output
  configure_autostart
  print_summary
}

main "$@"
