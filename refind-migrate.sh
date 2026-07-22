#!/usr/bin/env bash
set -Eeuo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# rEFInd UEFI bootloader migration — standalone script
# ═══════════════════════════════════════════════════════════════════════════════
#
# Split out of fedora-niri-setup.sh so bootloader changes can be run, tested,
# and re-run independently of the desktop setup.
#
# Package: rEFInd (case-sensitive) — available in Fedora's official repos.
#   Provides refind-install, which does the actual ESP deployment and NVRAM
#   registration: dnf install rEFInd; refind-install
#
# Secure Boot note: Fedora's rEFInd package is not signed with the Fedora
# Secure Boot key. If SB is enabled, this script runs refind-install with
# --localkeys (self-signs with a freshly generated local key). Because the
# script runs non-interactively, you must manually enroll that key as a MOK
# afterwards (exact command is printed in the summary). GRUB is NOT removed
# automatically until Secure Boot is resolved and rEFInd has been verified
# to boot.
#
# Usage:
#   ./refind-migrate.sh                                # interactive
#   ASSUME_YES=1 ./refind-migrate.sh                    # non-interactive
#   REFIND_REMOVE_GRUB=0 ./refind-migrate.sh            # install only, keep GRUB
#   ASSUME_YES=1 REFIND_REMOVE_GRUB=1 ./refind-migrate.sh   # full unattended migration
# ═══════════════════════════════════════════════════════════════════════════════

ASSUME_YES="${ASSUME_YES:-0}"
DNF_SKIP_UNAVAILABLE="${DNF_SKIP_UNAVAILABLE:-1}"

REFIND_REMOVE_GRUB="${REFIND_REMOVE_GRUB:-1}"
REFIND_TIMEOUT="${REFIND_TIMEOUT:-5}"
REFIND_ENTRY_LABEL="${REFIND_ENTRY_LABEL:-Fedora Linux}"
REFIND_ESP_SUBDIR="${REFIND_ESP_SUBDIR:-EFI/refind}"
REFIND_RECOVERY_DIR="${REFIND_RECOVERY_DIR:-/var/backups/bootloader-migration}"

# Runtime state — populated by preflight functions; not user-configurable.
_REFIND_ESP=""
_REFIND_ESP_DISK=""
_REFIND_ESP_PARTNUM=""
_REFIND_ARCH=""
_REFIND_EFI_NAME=""
_REFIND_SECURE_BOOT=""
_REFIND_BOOT_NUM=""

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_FILE:-$HOME/refind-migrate-$TIMESTAMP.log}"
SYSTEM_BACKUP_ROOT="${SYSTEM_BACKUP_ROOT:-/var/backups/fedora-niri-setup/$TIMESTAMP}"
DNF_BIN=""
DNF_SKIP_UNAVAILABLE_SUPPORTED=""

declare -a CHANGES=()
declare -a WARNINGS=()
declare -a SYSTEM_BACKUPS=()

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

exec > >(tee -a "$LOG_FILE") 2>&1

trap 'die "refind-migrate.sh failed on or near line $LINENO. Review $LOG_FILE, fix the reported problem, then re-run the script."' ERR

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
  rpm -q "$1" >/dev/null 2>&1
}

run_sudo() {
  sudo "$@"
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

prepare_runtime() {
  run_sudo install -d -m 0755 "$SYSTEM_BACKUP_ROOT"
  run_sudo -v
  log "Log file: $LOG_FILE"
  log "System backups: $SYSTEM_BACKUP_ROOT"
}

refind_check_uefi() {
  [[ -d /sys/firmware/efi ]] || \
    die "This system is not booted in UEFI mode (/sys/firmware/efi absent). rEFInd requires UEFI."
  log "UEFI mode confirmed."
}

refind_check_deps() {
  local missing=()
  local cmd
  for cmd in efibootmgr findmnt lsblk od; do
    have_command "$cmd" || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    dnf_install_best_effort efibootmgr util-linux || true
    for cmd in "${missing[@]}"; do
      have_command "$cmd" || die "Required command not available after install attempt: $cmd"
    done
  fi
}

refind_detect_esp() {
  local esp="" fstype dev candidate
  local esp_type_guid="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"

  # 1. Well-known mountpoints first.
  for candidate in /boot/efi /efi /boot; do
    if mountpoint -q "$candidate" 2>/dev/null; then
      fstype="$(findmnt -n -o FSTYPE "$candidate" 2>/dev/null || true)"
      if [[ "$fstype" == "vfat" ]]; then
        esp="$candidate"
        break
      fi
    fi
  done

  # 2. Any mounted vfat filesystem that looks like an ESP (has an EFI/ dir).
  if [[ -z "$esp" ]]; then
    local target
    while IFS= read -r target; do
      [[ -n "$target" ]] || continue
      if [[ -d "${target}/EFI" || -d "${target}/efi" ]]; then
        esp="$target"
        break
      fi
    done < <(findmnt -rn -o TARGET --types vfat 2>/dev/null || true)
  fi

  # 3. GPT partition-type GUID fallback — identifies the ESP even if it's
  #    mounted somewhere unusual, and tells us if it exists but is unmounted.
  if [[ -z "$esp" ]]; then
    local esp_part esp_mount
    esp_part="$(lsblk -rno NAME,PARTTYPE 2>/dev/null | awk -v guid="$esp_type_guid" 'tolower($2) == guid {print $1; exit}')"
    if [[ -n "$esp_part" ]]; then
      esp_mount="$(lsblk -rno MOUNTPOINT "/dev/${esp_part}" 2>/dev/null | head -1)"
      if [[ -n "$esp_mount" ]]; then
        esp="$esp_mount"
      else
        die "Found an EFI System Partition (/dev/${esp_part}, by GPT type GUID) but it is not mounted. Mount it (e.g. 'sudo mount /dev/${esp_part} /boot/efi') and re-run."
      fi
    fi
  fi

  if [[ -z "$esp" ]]; then
    warn "ESP detection failed. Diagnostics:"
    warn "  Mounted vfat filesystems:"
    findmnt -rn -o TARGET,SOURCE,FSTYPE --types vfat 2>/dev/null | sed 's/^/    /' >&2 || true
    warn "  Partitions with GPT type GUID ${esp_type_guid}: (none matched)"
    warn "  All partitions (NAME, PARTTYPE, FSTYPE, MOUNTPOINTS):"
    lsblk -o NAME,PARTTYPE,FSTYPE,MOUNTPOINTS 2>/dev/null | sed 's/^/    /' >&2 || true
    die "Cannot detect EFI System Partition. Ensure it is mounted (vfat) and re-run."
  fi
  _REFIND_ESP="$esp"

  dev="$(findmnt -n -o SOURCE "$esp" 2>/dev/null || true)"
  [[ -n "$dev" ]] || die "Cannot determine block device backing ESP at $esp."
  dev="$(realpath "$dev" 2>/dev/null || printf '%s' "$dev")"

  local pkname partnum
  pkname="$(lsblk -rndo PKNAME "$dev" 2>/dev/null | head -1 || true)"
  partnum="$(lsblk -rndo PARTN "$dev" 2>/dev/null | head -1 || true)"
  pkname="${pkname//[[:space:]]/}"
  partnum="${partnum//[[:space:]]/}"

  if [[ -n "$pkname" && -n "$partnum" ]]; then
    _REFIND_ESP_DISK="/dev/$pkname"
    _REFIND_ESP_PARTNUM="$partnum"
  elif [[ "$dev" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
    _REFIND_ESP_DISK="${BASH_REMATCH[1]}"
    _REFIND_ESP_PARTNUM="${BASH_REMATCH[2]}"
  elif [[ "$dev" =~ ^(/dev/[a-z]+)([0-9]+)$ ]]; then
    _REFIND_ESP_DISK="${BASH_REMATCH[1]}"
    _REFIND_ESP_PARTNUM="${BASH_REMATCH[2]}"
  else
    die "Cannot parse disk/partition from $dev. Set REFIND_ESP_DISK and REFIND_ESP_PARTNUM manually."
  fi

  [[ -b "$_REFIND_ESP_DISK" ]] || die "Detected disk $_REFIND_ESP_DISK is not a block device."
  log "ESP: $_REFIND_ESP (device: $dev, disk: $_REFIND_ESP_DISK, part: $_REFIND_ESP_PARTNUM)."
}

refind_detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64)  _REFIND_ARCH="x64";  _REFIND_EFI_NAME="refind_x64.efi"  ;;
    aarch64) _REFIND_ARCH="aa64"; _REFIND_EFI_NAME="refind_aa64.efi" ;;
    i?86)    _REFIND_ARCH="ia32"; _REFIND_EFI_NAME="refind_ia32.efi" ;;
    *) die "Unsupported architecture for rEFInd: $machine." ;;
  esac
  log "Arch: $machine → rEFInd binary: $_REFIND_EFI_NAME."
}

refind_check_secure_boot() {
  local sb_byte=""
  local sb_var="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"

  if [[ -r "$sb_var" ]]; then
    sb_byte="$(od -An -tu1 -j4 -N1 "$sb_var" 2>/dev/null | tr -d ' \n' || true)"
  elif have_command mokutil; then
    mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled" && sb_byte="1" || sb_byte="0"
  fi

  case "$sb_byte" in
    1) _REFIND_SECURE_BOOT="enabled"  ;;
    0) _REFIND_SECURE_BOOT="disabled" ;;
    *) _REFIND_SECURE_BOOT="unknown"  ;;
  esac
  log "Secure Boot: $_REFIND_SECURE_BOOT."

  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
    warn "Secure Boot is ENABLED. Fedora's rEFInd package is not signed with the Fedora"
    warn "Secure Boot key, so refind-install will be run with --localkeys, which generates"
    warn "a local signing key and self-signs the rEFInd binaries with it."
    warn "Because this script runs refind-install non-interactively (--yes), the MOK"
    warn "enrollment prompt is skipped — you must enroll the key yourself after this run"
    warn "finishes (exact command is printed in the summary below). Until that key is"
    warn "enrolled and the system has rebooted successfully with rEFInd, GRUB will NOT"
    warn "be removed automatically."
  fi
}

refind_resolve_cmdline() {
  local cmdline=""

  if [[ -s /etc/kernel/cmdline ]]; then
    cmdline="$(tr -s '[:space:]' ' ' </etc/kernel/cmdline | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$cmdline" ]] && printf '%s\n' "$cmdline" && return 0
  fi

  local bls_dir
  for bls_dir in /boot/loader/entries /boot/efi/loader/entries /efi/loader/entries; do
    [[ -d "$bls_dir" ]] || continue
    local bls_file
    bls_file="$(find "$bls_dir" -maxdepth 1 -name '*.conf' ! -name '*rescue*' -print 2>/dev/null \
                | sort -rV | head -1 || true)"
    if [[ -n "$bls_file" ]]; then
      cmdline="$(awk '/^options[[:space:]]/ { sub(/^options[[:space:]]+/,""); print; exit }' "$bls_file" \
                 | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -n "$cmdline" ]] && printf '%s\n' "$cmdline" && return 0
    fi
  done

  cmdline="$(sed -E 's/(^|[[:space:]])BOOT_IMAGE=[^[:space:]]*/\1/g' /proc/cmdline \
             | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$cmdline" ]] || die "Could not resolve a non-empty kernel command line from any source."
  printf '%s\n' "$cmdline"
}

refind_install_package() {
  # Package name is 'rEFInd' (case-sensitive) in Fedora 44.
  log "Installing rEFInd package from Fedora repositories."
  dnf_install rEFInd || die "Failed to install rEFInd. Check repo access and try: dnf info rEFInd."

  have_command refind-install || \
    die "refind-install not found after installing rEFInd (expected from rEFInd-tools)."

  # refind-install auto-detects the ESP, copies the EFI binary, icons, and
  # filesystem drivers, writes a starter refind.conf and /boot/refind_linux.conf,
  # and registers (and de-duplicates) the UEFI NVRAM entry itself — including
  # placing it first in BootOrder. We overlay our own refind.conf and
  # refind_linux.conf afterwards for consistent, predictable settings.
  local install_args=(--yes)
  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
    install_args+=(--localkeys)
    # --localkeys re-signs the rEFInd binaries with sbsign, which is not one
    # of rEFInd's own dependencies.
    have_command sbsign || dnf_install_best_effort sbsigntools
    have_command sbsign || die "sbsign (from sbsigntools) is required for --localkeys but could not be installed."
  fi

  log "Running: sudo refind-install ${install_args[*]}"
  run_sudo refind-install "${install_args[@]}" || \
    die "refind-install failed. Review the output above for the specific error."

  local esp_dir="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}"
  local efi_dest="${esp_dir}/${_REFIND_EFI_NAME}"
  run_sudo test -s "$efi_dest" || \
    die "refind-install completed, but ${efi_dest} is missing or empty."
  log "rEFInd installed at: $efi_dest."

  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
    record_change "Installed rEFInd with a locally generated Secure Boot key (--localkeys). MOK enrollment is still required — see summary."
  fi
}

refind_write_conf() {
  local esp_dir="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}"
  local conf_dest="${esp_dir}/refind.conf"

  backup_system_path "$conf_dest"

  local tmp; tmp="$(mktemp)"
  cat >"$tmp" <<EOF
# rEFInd configuration — written by refind-migrate.sh on ${TIMESTAMP}
# Delete this file and re-run the script to regenerate it.

timeout ${REFIND_TIMEOUT}

# Auto-detect all Linux kernels on all readable volumes.
scan_all_linux_kernels true

# Show each kernel as a separate entry (not folded by version).
fold_linux_kernels false

# Recognise kernels stored under these extra name patterns.
extra_kernel_version_strings linux,linux-lts,linux-hardened,linux-zen

# Skip volumes labelled as recovery/diagnostic environments.
dont_scan_volumes "Recovery,RECOVERY,WRE"

# Hide rescue kernels from the boot menu.
dont_scan_files rescue,fallback

# Boot options come from /boot/refind_linux.conf next to each kernel.
# NVRAM is managed by refind-install/efibootmgr, not by rEFInd itself.
use_nvram false

# Default to the most recently booted entry.
default_selection lastbooted

# Let the firmware choose the graphics resolution.
resolution auto
EOF
  run_sudo install -m 0644 "$tmp" "$conf_dest"
  rm -f "$tmp"
  log "Wrote rEFInd config: $conf_dest."
}

refind_write_linux_conf() {
  local cmdline
  cmdline="$(refind_resolve_cmdline)"
  local cmdline_verbose
  cmdline_verbose="$(printf '%s' "$cmdline" | sed 's/ quiet\b//g; s/ splash\b//g; s/ rhgb\b//g' | tr -s ' ')"

  local conf_dest="/boot/refind_linux.conf"
  backup_system_path "$conf_dest"

  local tmp; tmp="$(mktemp)"
  cat >"$tmp" <<EOF
# /boot/refind_linux.conf — per-kernel rEFInd boot options
# Written by refind-migrate.sh on ${TIMESTAMP}.
# Edit this file to customise kernel parameters.
# Format:  "Menu label"  "kernel options"

"Boot normally"            "${cmdline}"
"Boot verbose"             "${cmdline_verbose} systemd.show_status=1"
"Boot to single-user"      "${cmdline} single"
"Boot to emergency shell"  "${cmdline} systemd.unit=emergency.target"
EOF
  run_sudo install -m 0644 "$tmp" "$conf_dest"
  rm -f "$tmp"
  log "Wrote /boot/refind_linux.conf."
  log "Kernel cmdline: ${cmdline}."
}

refind_locate_nvram_entry() {
  # refind-install already created (or reused) the NVRAM entry and placed it
  # first in BootOrder. This just finds its Boot#### number for our own
  # validation/removal logic, normalizes its label, and re-asserts BootOrder
  # as a defense-in-depth check (idempotent — safe if already correct).
  have_command efibootmgr || die "efibootmgr is required to validate the rEFInd NVRAM entry."

  local boot_entry boot_num
  _REFIND_BOOT_NUM=""
  while IFS= read -r boot_entry; do
    [[ "$boot_entry" =~ ^Boot([0-9A-Fa-f]{4}) ]] || continue
    boot_num="${BASH_REMATCH[1]}"
    if echo "$boot_entry" | grep -qi "refind"; then
      _REFIND_BOOT_NUM="$boot_num"
      break
    fi
  done < <(run_sudo efibootmgr 2>/dev/null || true)
  [[ -n "$_REFIND_BOOT_NUM" ]] || die "No rEFInd NVRAM entry found after refind-install. Check efibootmgr output above."

  if [[ -n "$REFIND_ENTRY_LABEL" ]]; then
    local current_label
    current_label="$(run_sudo efibootmgr 2>/dev/null | sed -n "s/^Boot${_REFIND_BOOT_NUM}\*\{0,1\}[[:space:]]*//p" | head -1)"
    if [[ "$current_label" != "$REFIND_ENTRY_LABEL" ]]; then
      run_sudo efibootmgr --bootnum "$_REFIND_BOOT_NUM" --label "$REFIND_ENTRY_LABEL" >/dev/null || \
        warn "Could not rename NVRAM entry Boot${_REFIND_BOOT_NUM} to '${REFIND_ENTRY_LABEL}'."
    fi
  fi

  local cur_order first filtered new_order
  cur_order="$(run_sudo efibootmgr 2>/dev/null | awk '/^BootOrder:/{print $2}' || true)"
  first="$(printf '%s' "$cur_order" | cut -d, -f1)"
  if [[ "${first^^}" != "${_REFIND_BOOT_NUM^^}" ]]; then
    filtered="$(printf '%s' "$cur_order" | tr ',' '\n' \
                | grep -iv "^${_REFIND_BOOT_NUM}$" | tr '\n' ',' | sed 's/,$//')"
    new_order="${_REFIND_BOOT_NUM}${filtered:+,${filtered}}"
    run_sudo efibootmgr --bootorder "$new_order" || \
      warn "Could not set BootOrder. Set manually: sudo efibootmgr --bootorder ${new_order}"
    log "Moved rEFInd to first in BootOrder (${new_order})."
  fi

  log "rEFInd NVRAM entry: Boot${_REFIND_BOOT_NUM}."
  record_change "rEFInd registered as Boot${_REFIND_BOOT_NUM}, first in BootOrder."
}

refind_validate() {
  local errors=0
  log "Validating rEFInd installation…"

  local efi_bin="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}/${_REFIND_EFI_NAME}"
  if run_sudo test -s "$efi_bin"; then
    log "  [✓] EFI binary present: $efi_bin"
  else
    warn "  [✗] EFI binary missing or empty: $efi_bin"
    errors=$(( errors + 1 ))
  fi

  local conf="${_REFIND_ESP}/${REFIND_ESP_SUBDIR}/refind.conf"
  if run_sudo test -f "$conf"; then
    log "  [✓] refind.conf: $conf"
  else
    warn "  [✗] refind.conf missing: $conf"
    errors=$(( errors + 1 ))
  fi

  if [[ -f /boot/refind_linux.conf ]]; then
    log "  [✓] /boot/refind_linux.conf present"
  else
    warn "  [✗] /boot/refind_linux.conf missing"
    errors=$(( errors + 1 ))
  fi

  if [[ -n "$_REFIND_BOOT_NUM" ]] && \
     run_sudo efibootmgr 2>/dev/null | grep -q "Boot${_REFIND_BOOT_NUM}"; then
    log "  [✓] NVRAM entry Boot${_REFIND_BOOT_NUM} present"
  else
    warn "  [✗] NVRAM entry Boot${_REFIND_BOOT_NUM:-???} not found"
    errors=$(( errors + 1 ))
  fi

  local first
  first="$(run_sudo efibootmgr 2>/dev/null | awk '/^BootOrder:/{split($2,a,","); print a[1]}' || true)"
  if [[ "${first^^}" == "${_REFIND_BOOT_NUM^^}" ]]; then
    log "  [✓] rEFInd is first in BootOrder"
  else
    warn "  [✗] rEFInd (Boot${_REFIND_BOOT_NUM}) is not first in BootOrder (first: Boot${first})"
    errors=$(( errors + 1 ))
  fi

  local kcount=0
  kcount="$(find /boot -maxdepth 1 -name 'vmlinuz-*' ! -name '*rescue*' -print 2>/dev/null | wc -l || echo 0)"
  kcount="${kcount//[[:space:]]/}"
  if (( kcount > 0 )); then
    log "  [✓] Found ${kcount} bootable kernel(s) in /boot"
  else
    warn "  [✗] No non-rescue kernels found in /boot"
    errors=$(( errors + 1 ))
  fi

  (( errors == 0 )) || die "rEFInd validation failed ($errors error(s)). Fix the warnings above before removing GRUB."
  log "rEFInd validation passed."
}

refind_backup_grub() {
  local bdir="${REFIND_RECOVERY_DIR}/${TIMESTAMP}"
  run_sudo install -d -m 0750 "$bdir"

  local efi_fedora="${_REFIND_ESP}/EFI/fedora"
  if [[ -d "$efi_fedora" ]]; then
    run_sudo cp -a "$efi_fedora" "${bdir}/EFI-fedora"
    log "Backed up $efi_fedora → ${bdir}/EFI-fedora."
  fi

  local f
  for f in /etc/default/grub /boot/grub2/grub.cfg /boot/grub2/grubenv; do
    [[ -f "$f" ]] && run_sudo cp -a "$f" "${bdir}/" && log "Backed up $f."
  done

  run_sudo efibootmgr -v 2>/dev/null >"${bdir}/efibootmgr-pre-removal.txt" || true
  log "Saved efibootmgr state → ${bdir}/efibootmgr-pre-removal.txt."
  printf '%s\n' "$bdir"
}

refind_remove_grub() {
  local bdir="$1"

  # Remove Fedora GRUB NVRAM entries — only those whose loader path contains
  # EFI\fedora (verbose efibootmgr output includes the loader path).
  log "Removing Fedora GRUB NVRAM entries."
  local boot_entry boot_num
  while IFS= read -r boot_entry; do
    [[ "$boot_entry" =~ ^Boot([0-9A-Fa-f]{4}) ]] || continue
    boot_num="${BASH_REMATCH[1]}"
    [[ "${boot_num^^}" == "${_REFIND_BOOT_NUM^^}" ]] && continue
    if echo "$boot_entry" | grep -qiE '\\EFI\\fedora\\|File.*fedora'; then
      log "  Removing GRUB NVRAM entry Boot${boot_num}."
      run_sudo efibootmgr --bootnum "$boot_num" --delete-bootnum 2>/dev/null || \
        warn "  Could not remove Boot${boot_num}."
      record_change "Removed GRUB NVRAM entry Boot${boot_num}."
    fi
  done < <(run_sudo efibootmgr -v 2>/dev/null || true)

  # Remove the GRUB *bootloader* EFI packages only. grub2-common and
  # grub2-tools/grub2-tools-minimal are NOT removed:
  #   - grubby requires (grub2-tools OR grub2-tools-minimal), and both of
  #     those require grub2-common — dnf will refuse (correctly) to remove
  #     grub2-common while grubby stays installed, and the WHOLE batch
  #     removal aborts if it's included alongside removable packages.
  #   - grub2-common ships /usr/lib/kernel/install.d/20-grub.install and
  #     95-set-boot-entry.install, which are what actually WRITE
  #     /boot/loader/entries/*.conf BLS files on every kernel install —
  #     this is Fedora's kernel-install plumbing, unrelated to which
  #     bootloader (GRUB, rEFInd, ...) ultimately reads those entries.
  #     Removing it would break BLS entry generation for future kernels.
  #   - 20-grub.install calls grub2-mkrelpath, which ships only in the full
  #     grub2-tools package (not -minimal) — confirmed by inspecting both
  #     packages' file lists — and Fedora 44 has no /sbin/new-kernel-pkg
  #     fallback, so that code path always runs. Removing grub2-tools would
  #     break BLS entry paths on the next kernel update.
  # ⚠ Verify package names against: dnf list installed 'grub2*'
  local grub_pkgs=(
    grub2-efi-x64
    grub2-efi-x64-cdboot
    grub2-efi-aa64
    grub2-efi-ia32
    grub2-efi-x64-modules
    grub2-tools-extra
  )
  local to_remove=() pkg
  for pkg in "${grub_pkgs[@]}"; do
    package_installed "$pkg" && to_remove+=("$pkg")
  done
  if (( ${#to_remove[@]} > 0 )); then
    log "Removing GRUB packages: ${to_remove[*]}."
    run_sudo "$DNF_BIN" remove -y "${to_remove[@]}" || \
      warn "Some GRUB packages could not be removed: ${to_remove[*]}."
    record_change "Removed GRUB packages: ${to_remove[*]}."
  else
    log "No target GRUB packages were installed."
  fi

  # grub2-efi-x64 owns /boot/grub2/grubenv. If its removal deleted that file,
  # recreate an empty valid env block so 95-set-boot-entry.install's
  # `grub2-editenv - set ...` calls (still exercised by every kernel install,
  # since grub2-common's plugins are kept) have a valid file to operate on.
  if have_command grub2-editenv && [[ ! -f /boot/grub2/grubenv ]]; then
    run_sudo grub2-editenv /boot/grub2/grubenv create && \
      log "Recreated empty /boot/grub2/grubenv (still used by kernel-install BLS bookkeeping)."
  fi

  # Clean up GRUB's generated (non-package-owned) leftovers under /boot/grub2:
  # grub.cfg is dead now that GRUB never runs, and themes/ is only ever our
  # own Sleek theme copy. Everything else in /boot/grub2 (grubenv, and any
  # grub2-common-owned files) is left alone — see comment above.
  local leftover
  for leftover in /boot/grub2/grub.cfg /boot/grub2/themes; do
    if run_sudo test -e "$leftover"; then
      run_sudo rm -rf "$leftover"
      log "  Removed: $leftover."
      record_change "Removed GRUB leftover: $leftover."
    fi
  done

  # Remove GRUB EFI files from the ESP.  Keep shimx64.efi and MokManager.efi —
  # shim is needed for Secure Boot and for signing other EFI tools.
  local efi_fedora="${_REFIND_ESP}/EFI/fedora"
  if [[ -d "$efi_fedora" ]]; then
    local grub_files=(
      grubx64.efi grubaa64.efi grubenv grub.cfg
      fonts locale
    )
    local gf
    for gf in "${grub_files[@]}"; do
      local fp="${efi_fedora}/${gf}"
      if run_sudo test -e "$fp"; then
        run_sudo rm -rf "$fp"
        log "  Removed: $fp."
        record_change "Removed GRUB EFI file: $fp."
      fi
    done
    # Remove the directory only if empty (shim/MOK files may remain)
    if [[ -z "$(run_sudo find "$efi_fedora" -maxdepth 1 -mindepth 1 -print 2>/dev/null | head -1)" ]]; then
      run_sudo rmdir "$efi_fedora" 2>/dev/null || true
      log "  Removed empty directory: $efi_fedora."
    else
      log "  Kept $efi_fedora (non-GRUB files remain, e.g. shim/MokManager)."
    fi
  fi

  log "GRUB removal complete. Recovery backup: $bdir."
}

refind_print_summary() {
  local bdir="${1:-n/a}"

  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_CYAN" "$COLOR_RESET"
  printf '%s  rEFInd Bootloader Summary%s\n' "$COLOR_CYAN" "$COLOR_RESET"
  printf '%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_CYAN" "$COLOR_RESET"
  printf '\n'
  printf '  EFI System Partition : %s\n'            "$_REFIND_ESP"
  printf '  rEFInd EFI binary    : %s/%s/%s\n'     "$_REFIND_ESP" "$REFIND_ESP_SUBDIR" "$_REFIND_EFI_NAME"
  printf '  rEFInd config        : %s/%s/refind.conf\n' "$_REFIND_ESP" "$REFIND_ESP_SUBDIR"
  printf '  Kernel options file  : /boot/refind_linux.conf\n'
  printf '  Secure Boot state    : %s\n'            "$_REFIND_SECURE_BOOT"
  printf '  NVRAM entry          : Boot%s  (%s)\n' "${_REFIND_BOOT_NUM:-???}" "$REFIND_ENTRY_LABEL"
  printf '  GRUB backup dir      : %s\n'            "$bdir"
  printf '\n'
  printf '  %sCurrent UEFI boot order:%s\n' "$COLOR_BOLD" "$COLOR_RESET"
  run_sudo efibootmgr 2>/dev/null | grep -E '^Boot[0-9A-Fa-f]{4}' | sed 's/^/    /' || true
  printf '\n'
  printf '  %sRecovery (if rEFInd does not boot):%s\n' "$COLOR_YELLOW" "$COLOR_RESET"
  printf '  1. Boot Fedora live media.\n'
  printf '  2. Mount the ESP and restore GRUB EFI files:\n'
  printf '       sudo mount %s /mnt\n' "$_REFIND_ESP_DISK"
  printf '       sudo cp -a %s/EFI-fedora /mnt/EFI/fedora\n' "$bdir"
  printf '  3. Re-register the GRUB NVRAM entry:\n'
  printf '       sudo efibootmgr --create --disk %s --part %s \\\n' \
    "$_REFIND_ESP_DISK" "$_REFIND_ESP_PARTNUM"
  printf '         --label "fedora" --loader "\\\\EFI\\\\fedora\\\\shimx64.efi"\n'
  printf '  4. Reboot.\n'
  if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
    printf '\n  %sSecure Boot — action required before rEFInd will start:%s\n' "$COLOR_YELLOW" "$COLOR_RESET"
    printf '  refind-install was run with --localkeys, which generated a local signing\n'
    printf '  key and self-signed the rEFInd binaries. That key is NOT yet trusted by\n'
    printf '  your firmware. Option A (recommended) — enroll it as a MOK:\n'
    printf '    sudo mokutil --import /etc/refind.d/keys/refind_local.cer\n'
    printf '    (you will set a one-time password, then reboot and enroll it at the\n'
    printf '     blue MokManager screen using that password)\n'
    printf '  Option B — disable Secure Boot in your UEFI firmware settings instead.\n'
  fi
  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n' "$COLOR_CYAN" "$COLOR_RESET"
}

install_refind() {
  warn "REPLACING BOOTLOADER: rEFInd will become the primary UEFI boot manager."
  warn "Have a Fedora live USB ready in case of boot failure."
  if [[ "$ASSUME_YES" != "1" ]]; then
    ask_yes_no "Continue with rEFInd bootloader migration?" y || {
      log "rEFInd installation cancelled by user."
      return 0
    }
  fi

  refind_check_uefi
  refind_check_deps
  refind_detect_esp
  refind_detect_arch
  refind_check_secure_boot

  refind_install_package
  refind_locate_nvram_entry
  refind_write_conf
  refind_write_linux_conf
  refind_validate

  local bdir="n/a (GRUB not removed)"
  if [[ "$REFIND_REMOVE_GRUB" == "1" ]]; then
    if [[ "$_REFIND_SECURE_BOOT" == "enabled" ]]; then
      warn "Secure Boot is enabled — GRUB will NOT be removed automatically."
      warn "Resolve Secure Boot (see summary below), verify rEFInd boots, then re-run"
      warn "with REFIND_REMOVE_GRUB=1 to skip reinstall and only perform GRUB removal."
    else
      bdir="$(refind_backup_grub)"
      refind_remove_grub "$bdir"
      log "Post-removal validation."
      refind_validate
    fi
  else
    log "GRUB not removed (REFIND_REMOVE_GRUB=0). Verify boot, then re-run with REFIND_REMOVE_GRUB=1."
  fi

  refind_print_summary "$bdir"
  record_change "Installed rEFInd UEFI bootloader."
}

print_summary() {
  local item

  printf '\n%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  rEFInd migration complete%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '%s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  printf '\n'
  printf '  Log:            %s\n' "$LOG_FILE"
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
  require_fedora
  prepare_runtime
  install_refind
  print_summary
}

main "$@"
