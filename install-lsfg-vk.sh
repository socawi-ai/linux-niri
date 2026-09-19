#!/usr/bin/env bash
set -Eeuo pipefail

# Builds and installs lsfg-vk (https://lsfg-vk.dev) from source: a Vulkan
# layer that runs Lossless Scaling's frame-generation algorithm on Linux.
# Follows the official "Building from Source" guide for Fedora:
# https://lsfg-vk.dev/docs/installation/building-from-source/
#
# Fully standalone -- run this by itself, once, on a machine that already
# has its desktop set up. Not called by fedora-niri-setup.sh, and does not
# require it to have been run first. Fedora only -- Arch has its own AUR
# packages (lsfg-vk / lsfg-vk-bin / lsfg-vk-git) and doesn't need this.
#
# Requires Lossless Scaling (https://store.steampowered.com/app/993090)
# purchased and installed through Steam -- lsfg-vk is a re-implementation
# of its Vulkan layer, not a replacement for the app itself, and needs the
# "lsfg-vk.dll" file that ships inside it. That app, and switching it to
# its "lsfg-vk" Steam beta branch, are manual steps this script cannot do
# for you -- see the summary printed at the end.

LSFG_VK_REPO_URL="${LSFG_VK_REPO_URL:-https://git.lsfg-vk.dev/lsfg-vk.git}"
LSFG_VK_REPO_TAG="${LSFG_VK_REPO_TAG:-}"
LSFG_VK_BUILD_DIR="${LSFG_VK_BUILD_DIR:-$HOME/.cache/install-lsfg-vk/lsfg-vk}"
LSFG_VK_INSTALL_PREFIX="${LSFG_VK_INSTALL_PREFIX:-/usr/local}"
LSFG_VK_BUILD_TYPE="${LSFG_VK_BUILD_TYPE:-Release}"
LSFG_VK_ENABLE_LTO="${LSFG_VK_ENABLE_LTO:-1}"
LSFG_VK_BUILD_UI="${LSFG_VK_BUILD_UI:-1}"
INSTALL_VULKAN_TOOLS="${INSTALL_VULKAN_TOOLS:-1}"

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
  grep -qi '^ID=fedora' /etc/os-release || die "This script only supports Fedora. Arch has its own lsfg-vk/lsfg-vk-bin/lsfg-vk-git AUR packages -- use those instead."
  have_command dnf || die "dnf was not found."
}

install_dependencies() {
  log "Installing build dependencies."
  sudo dnf install -y \
    git curl \
    llvm clang clang-tools-extra \
    cmake ninja-build pkgconf-pkg-config \
    vulkan-loader-devel \
    mesa-libGL-devel \
    qt6-qtbase-devel \
    qt6-qttools-devel \
    qt6-qtdeclarative-devel \
    || die "Could not install build dependencies."
  record_change "Installed lsfg-vk build dependencies."

  [[ "$INSTALL_VULKAN_TOOLS" == "1" ]] || return 0
  if ! rpm -q vulkan-tools >/dev/null 2>&1; then
    if sudo dnf install -y vulkan-tools; then
      record_change "Installed vulkan-tools (for vkcube, to verify the layer loads)."
    else
      warn "Could not install vulkan-tools; you won't be able to verify with vkcube."
    fi
  fi
}

clone_or_update_repo() {
  if [[ -d "$LSFG_VK_BUILD_DIR/.git" ]]; then
    log "Updating existing lsfg-vk checkout at $LSFG_VK_BUILD_DIR."
    git -C "$LSFG_VK_BUILD_DIR" fetch --tags origin || die "Could not fetch updates for lsfg-vk."
    if [[ -n "$LSFG_VK_REPO_TAG" ]]; then
      git -C "$LSFG_VK_BUILD_DIR" checkout "tags/$LSFG_VK_REPO_TAG" || die "Could not check out tag $LSFG_VK_REPO_TAG."
    else
      git -C "$LSFG_VK_BUILD_DIR" checkout main || git -C "$LSFG_VK_BUILD_DIR" checkout master || die "Could not check out the default branch."
      git -C "$LSFG_VK_BUILD_DIR" pull --ff-only || die "Could not pull the latest lsfg-vk source."
    fi
  else
    log "Cloning lsfg-vk from $LSFG_VK_REPO_URL."
    mkdir -p "$(dirname "$LSFG_VK_BUILD_DIR")"
    git clone "$LSFG_VK_REPO_URL" "$LSFG_VK_BUILD_DIR" || die "Could not clone lsfg-vk."
    if [[ -n "$LSFG_VK_REPO_TAG" ]]; then
      git -C "$LSFG_VK_BUILD_DIR" checkout "tags/$LSFG_VK_REPO_TAG" || die "Could not check out tag $LSFG_VK_REPO_TAG."
    fi
    record_change "Cloned lsfg-vk into $LSFG_VK_BUILD_DIR."
  fi
}

build_and_install() {
  local lto_flag ui_flag
  lto_flag="OFF"
  [[ "$LSFG_VK_ENABLE_LTO" == "1" ]] && lto_flag="ON"
  ui_flag="OFF"
  [[ "$LSFG_VK_BUILD_UI" == "1" ]] && ui_flag="ON"

  log "Configuring the build (prefix: $LSFG_VK_INSTALL_PREFIX, type: $LSFG_VK_BUILD_TYPE, UI: $ui_flag)."
  (
    cd "$LSFG_VK_BUILD_DIR"
    cmake -B build -G Ninja \
      -DCMAKE_BUILD_TYPE="$LSFG_VK_BUILD_TYPE" \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION="$lto_flag" \
      -DCMAKE_INSTALL_PREFIX="$LSFG_VK_INSTALL_PREFIX" \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DLSFGVK_BUILD_UI="$ui_flag"
  ) || die "CMake configuration failed."

  log "Building lsfg-vk (this can take a while)."
  cmake --build "$LSFG_VK_BUILD_DIR/build" || die "Build failed."

  log "Installing to $LSFG_VK_INSTALL_PREFIX."
  sudo cmake --install "$LSFG_VK_BUILD_DIR/build" || die "Install failed."
  record_change "Built and installed lsfg-vk to $LSFG_VK_INSTALL_PREFIX."
}

run_healthcheck() {
  local cli_bin
  cli_bin="$(command -v lsfg-vk-cli || true)"
  [[ -n "$cli_bin" ]] || {
    warn "lsfg-vk-cli not found on PATH after install; skipping healthcheck."
    return 0
  }

  log "Running lsfg-vk-cli healthcheck."
  "$cli_bin" healthcheck || warn "lsfg-vk-cli healthcheck reported issues -- see output above."
}

print_summary() {
  printf '\n%s  ────────────────────────────────────────────%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  lsfg-vk build/install complete%s\n' "$COLOR_GREEN" "$COLOR_RESET"
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

  printf '\n  %sManual steps that cannot be scripted:%s\n' "$COLOR_DIM" "$COLOR_RESET"
  printf '  1. Own and install Lossless Scaling on Steam, then switch it to the\n'
  printf '     "lsfg-vk" beta branch (Steam > Library > Lossless Scaling > right-click\n'
  printf '     > Properties > Betas). lsfg-vk looks for its "lsfg-vk.dll" in the\n'
  printf '     usual Steam library locations; if yours is nonstandard, set it via\n'
  printf '     the "dll" key under [global] in ~/.config/lsfg-vk/conf.toml.\n'
  printf '  2. Run "lsfg-vk-ui" (or ~/.local/bin/lsfg-vk-ui) to create a profile,\n'
  printf '     or launch a game with LSFGVK_PROFILE=<name> to pick one at runtime.\n'
  printf '  3. Verify the layer loads with: vkcube  (or DISABLE_LSFGVK=1 vkcube to\n'
  printf '     compare). Its pacing mode requires Vsync enabled to avoid duplicated\n'
  printf '     frames.\n'
  printf '  4. Full docs: https://lsfg-vk.dev/docs/getting-started/\n'
  printf '\n'
}

main() {
  require_fedora
  install_dependencies
  clone_or_update_repo
  build_and_install
  run_healthcheck
  print_summary
}

main "$@"
