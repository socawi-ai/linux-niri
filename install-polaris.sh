#!/usr/bin/env bash
set -Eeuo pipefail

# Installs Polaris (papi-ux's self-hosted GameStream host for Nova and
# Moonlight-compatible clients: https://github.com/papi-ux/polaris) from
# the latest GitHub release, runs its one-time host setup, and enables it
# to start on login.
#
# Fully standalone -- run this by itself, once, on a machine that already
# has its desktop set up. Not called by fedora-niri-setup.sh or
# arch-niri-setup.sh, and does not require either to have been run first.
#
# Replaces this repo's former Sunshine-based streaming setup
# (install-sunshine-beta.sh / install-sunshine.sh, both removed). Unlike
# Sunshine, Polaris launches games in its own dedicated headless
# compositor, isolated from your actual desktop session, and has a
# built-in Steam library scanner in its web UI -- steam-sunshine-sync.sh's
# external scan-and-sync-to-apps.json approach has no equivalent role here
# (see the Applications tab in Polaris's own web console instead).
#
# Installs from GitHub release packages, verified against the sha256
# digest GitHub publishes for each asset before installing:
#   Fedora: the "Polaris-fedoraNN-x86_64.rpm" asset matching your Fedora
#           version, via dnf. If no exact match exists (Polaris doesn't
#           publish a build for every Fedora release), falls back to
#           whatever Fedora build is published, with a warning -- set
#           POLARIS_ASSET_NAME to pick a specific one yourself.
#   Arch:   "Polaris-arch-x86_64.pkg.tar.zst", via pacman -U.
#
# Polaris also has installers for SteamOS, Ubuntu, Bazzite, openSUSE, and
# source builds (see https://papi-ux.com/docs/quickstart/) -- this script
# only automates Fedora and Arch, matching the rest of this repo.

AUTO_INSTALL_DEPENDENCIES="${AUTO_INSTALL_DEPENDENCIES:-1}"
ASSUME_YES="${ASSUME_YES:-1}"
ENABLE_POLARIS_AUTOSTART="${ENABLE_POLARIS_AUTOSTART:-1}"
POLARIS_REPO="${POLARIS_REPO:-papi-ux/polaris}"
POLARIS_ASSET_NAME="${POLARIS_ASSET_NAME:-}"

# Polaris's own docs: "Only use `polaris --setup-host --enable-kms` when
# the guide says your DRM/KMS capture path needs it." Off by default since
# it's explicitly situational, not a default -- if streaming doesn't work
# afterwards, consult https://papi-ux.com/docs/configuration/, then either
# set POLARIS_ENABLE_KMS=1 and re-run this script, or just run
# `sudo -H polaris --setup-host --enable-kms` yourself.
POLARIS_ENABLE_KMS="${POLARIS_ENABLE_KMS:-0}"

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

DISTRO="$(detect_distro)"

install_packages() {
  local -a pkgs=("$@")
  ((${#pkgs[@]})) || return 0

  case "$DISTRO" in
    fedora)
      have_command dnf || { warn "dnf was not found; cannot auto-install: ${pkgs[*]}."; return 1; }
      sudo dnf install -y "${pkgs[@]}" || { warn "Could not install: ${pkgs[*]}."; return 1; }
      ;;
    arch)
      have_command pacman || { warn "pacman was not found; cannot auto-install: ${pkgs[*]}."; return 1; }
      local args=(-S --needed)
      [[ "$ASSUME_YES" == "1" ]] && args+=(--noconfirm)
      sudo pacman "${args[@]}" "${pkgs[@]}" || { warn "Could not install: ${pkgs[*]}."; return 1; }
      ;;
  esac

  record_change "Installed: ${pkgs[*]}."
  return 0
}

ensure_command() {
  local cmd="$1" pkg="${2:-$1}"
  have_command "$cmd" && return 0
  [[ "$AUTO_INSTALL_DEPENDENCIES" == "1" ]] || return 1

  log "Installing missing dependency: $cmd."
  install_packages "$pkg"
  have_command "$cmd"
}

check_dependencies() {
  local -a missing=()
  ensure_command curl || missing+=(curl)
  ensure_command jq || missing+=(jq)
  have_command sha256sum || missing+=(sha256sum)
  have_command sudo || missing+=(sudo)
  ((${#missing[@]} == 0)) || die "Missing required command(s): ${missing[*]}."
}

fetch_latest_release() {
  local url="https://api.github.com/repos/$POLARIS_REPO/releases/latest"
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL -H 'Accept: application/vnd.github+json' "$url" -o "$tmp"; then
    rm -f "$tmp"
    die "Could not reach the GitHub API ($url) to find the latest Polaris release. Check your connection, or if you're being rate-limited, wait a bit and retry."
  fi
  jq -e . >/dev/null 2>&1 <"$tmp" || die "GitHub API response for $url was not valid JSON (rate-limited?)."
  printf '%s\n' "$tmp"
}

asset_url() {
  jq -r --arg n "$2" '.assets[] | select(.name == $n) | .browser_download_url' "$1"
}

asset_digest() {
  jq -r --arg n "$2" '.assets[] | select(.name == $n) | .digest // empty' "$1"
}

fedora_version() {
  grep -oP '^VERSION_ID=\K[0-9]+' /etc/os-release 2>/dev/null || true
}

pick_fedora_asset() {
  local json="$1" ver
  ver="$(fedora_version)"

  if [[ -n "$POLARIS_ASSET_NAME" ]]; then
    ASSET_NAME="$POLARIS_ASSET_NAME"
  elif [[ -n "$ver" ]] && jq -e --arg n "Polaris-fedora${ver}-x86_64.rpm" '.assets[] | select(.name == $n)' "$json" >/dev/null; then
    ASSET_NAME="Polaris-fedora${ver}-x86_64.rpm"
  else
    local -a names
    mapfile -t names < <(jq -r '.assets[] | select(.name | test("^Polaris-fedora[0-9]+-x86_64\\.rpm$")) | .name' "$json")
    case "${#names[@]}" in
      0) die "No Fedora .rpm asset found in the latest Polaris release ($POLARIS_REPO)." ;;
      1) ASSET_NAME="${names[0]}" ;;
      *) ASSET_NAME="$(printf '%s\n' "${names[@]}" | sed -E 's/^Polaris-fedora([0-9]+)-x86_64\.rpm$/\1 &/' | sort -k1,1n | tail -1 | cut -d' ' -f2-)" ;;
    esac
    warn "No Polaris build published for Fedora ${ver:-<unknown>}; falling back to $ASSET_NAME (may not match this system's libraries). Set POLARIS_ASSET_NAME to pick a different one."
  fi

  ASSET_URL="$(asset_url "$json" "$ASSET_NAME")"
  ASSET_DIGEST="$(asset_digest "$json" "$ASSET_NAME")"
  [[ -n "$ASSET_URL" && "$ASSET_URL" != "null" ]] || die "Asset $ASSET_NAME was not found in the latest Polaris release."
}

pick_arch_asset() {
  local json="$1"
  ASSET_NAME="${POLARIS_ASSET_NAME:-Polaris-arch-x86_64.pkg.tar.zst}"
  ASSET_URL="$(asset_url "$json" "$ASSET_NAME")"
  ASSET_DIGEST="$(asset_digest "$json" "$ASSET_NAME")"
  [[ -n "$ASSET_URL" && "$ASSET_URL" != "null" ]] || die "Asset $ASSET_NAME was not found in the latest Polaris release ($POLARIS_REPO)."
}

download_and_verify() {
  local url="$1" digest="$2" dest="$3"
  log "Downloading $(basename "$dest")."
  curl -fsSL -o "$dest" "$url" || die "Could not download $url."

  if [[ -z "$digest" ]]; then
    warn "No digest published for $(basename "$dest"); skipping integrity check."
    return 0
  fi

  local algo="${digest%%:*}" want="${digest#*:}" got
  case "$algo" in
    sha256)
      got="$(sha256sum "$dest" | awk '{print $1}')"
      [[ "$got" == "$want" ]] || die "Checksum mismatch for $(basename "$dest") (expected $want, got $got) -- refusing to install a corrupted or tampered download."
      log "Checksum verified ($algo)."
      ;;
    *)
      warn "Unrecognized digest algorithm '$algo' for $(basename "$dest"); skipping integrity check."
      ;;
  esac
}

install_polaris_fedora() {
  have_command dnf || die "dnf was not found."

  local json tag
  json="$(fetch_latest_release)"
  tag="$(jq -r '.tag_name' "$json")"
  log "Latest Polaris release: $tag."

  local ASSET_NAME ASSET_URL ASSET_DIGEST
  pick_fedora_asset "$json"

  local tmp_dir pkg
  tmp_dir="$(mktemp -d)"
  pkg="$tmp_dir/$ASSET_NAME"
  download_and_verify "$ASSET_URL" "$ASSET_DIGEST" "$pkg"

  log "Installing $ASSET_NAME."
  sudo dnf install -y "$pkg" || die "Could not install $ASSET_NAME."

  rm -rf "$tmp_dir" "$json"
  record_change "Installed Polaris $tag ($ASSET_NAME) from $POLARIS_REPO."
}

install_polaris_arch() {
  have_command pacman || die "pacman was not found."

  local json tag
  json="$(fetch_latest_release)"
  tag="$(jq -r '.tag_name' "$json")"
  log "Latest Polaris release: $tag."

  local ASSET_NAME ASSET_URL ASSET_DIGEST
  pick_arch_asset "$json"

  local tmp_dir pkg
  tmp_dir="$(mktemp -d)"
  pkg="$tmp_dir/$ASSET_NAME"
  download_and_verify "$ASSET_URL" "$ASSET_DIGEST" "$pkg"

  log "Installing $ASSET_NAME."
  local args=(-U)
  [[ "$ASSUME_YES" == "1" ]] && args+=(--noconfirm)
  sudo pacman "${args[@]}" "$pkg" || die "Could not install $ASSET_NAME."

  rm -rf "$tmp_dir" "$json"
  record_change "Installed Polaris $tag ($ASSET_NAME) from $POLARIS_REPO."
}

setup_host() {
  have_command polaris || die "polaris was not found in PATH after installation."

  local -a args=(--setup-host)
  if [[ "$POLARIS_ENABLE_KMS" == "1" ]]; then
    args+=(--enable-kms)
    log "Running host setup: polaris ${args[*]} (POLARIS_ENABLE_KMS=1)."
  else
    log "Running host setup: polaris ${args[*]}."
  fi

  sudo -H polaris "${args[@]}" || die "polaris ${args[*]} failed. Check the output above."
  record_change "Ran: polaris ${args[*]}."
}

configure_autostart() {
  [[ "$ENABLE_POLARIS_AUTOSTART" == "1" ]] || {
    log "Polaris autostart is disabled."
    return 0
  }

  have_command systemctl || {
    warn "systemctl was not found; skipping autostart setup."
    return 0
  }

  local uid
  uid="$(id -u)"
  if [[ -d "/run/user/$uid" ]]; then
    if systemctl --user enable --now polaris; then
      record_change "Enabled and started the polaris user service."
      return 0
    fi
    warn "Could not enable/start the polaris user service now."
  else
    if systemctl --user enable polaris; then
      warn "Enabled the polaris user service for autostart, but could not start it now because /run/user/$uid does not exist (no active login session)."
      return 0
    fi
    warn "Could not enable the polaris user service."
  fi
}

print_summary() {
  printf '\n%s  ────────────────────────────────────────────%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  Polaris install complete%s\n' "$COLOR_GREEN" "$COLOR_RESET"
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
  printf '  Open https://localhost:47990 in a browser, create the web account,\n'
  printf '  pair a client (Nova or Moonlight), and launch a title.\n'
  printf '\n  Config lives in ~/.config/polaris/ (polaris.conf, apps.json,\n'
  printf '  polaris_state.json). Steam games do not need a separate sync script --\n'
  printf '  add them from the web UI'"'"'s Applications tab (library scan + optional\n'
  printf '  SteamGridDB cover art), or launch Steam Big Picture directly.\n'
  printf '\n  If streaming does not capture correctly, see\n'
  printf '  https://papi-ux.com/docs/configuration/ about whether your setup needs\n'
  printf '  POLARIS_ENABLE_KMS=1 (re-run this script) or manually:\n'
  printf '  sudo -H polaris --setup-host --enable-kms\n'
  printf '\n'
}

main() {
  check_dependencies
  log "Detected distro: $DISTRO."

  case "$DISTRO" in
    fedora) install_polaris_fedora ;;
    arch) install_polaris_arch ;;
  esac

  setup_host
  configure_autostart
  print_summary
}

main "$@"
