#!/usr/bin/env bash
set -Eeuo pipefail

STEAM_DRIVE_UUID="${STEAM_DRIVE_UUID:-}"
STEAM_DRIVE_MOUNT="${STEAM_DRIVE_MOUNT:-/mnt/steam}"
STEAM_DRIVE_FSTYPE="${STEAM_DRIVE_FSTYPE:-ext4}"
STEAM_DRIVE_OPTIONS="${STEAM_DRIVE_OPTIONS:-defaults,noatime}"
ASSUME_YES="${ASSUME_YES:-0}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
FSTAB_BACKUP="/etc/fstab.bak.$TIMESTAMP"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
  exit 1
}

run_sudo() {
  sudo "$@"
}

require_normal_user() {
  [[ "$EUID" -ne 0 ]] || die "Run this script as your normal user, not directly as root."
  command -v findmnt >/dev/null 2>&1 || die "findmnt is required."
  command -v blkid >/dev/null 2>&1 || die "blkid is required."
  command -v lsblk >/dev/null 2>&1 || die "lsblk is required."
}

choose_steam_drive_uuid() {
  [[ -z "$STEAM_DRIVE_UUID" ]] || return 0
  [[ "$ASSUME_YES" != "1" ]] || die "STEAM_DRIVE_UUID is required when ASSUME_YES=1."
  [[ -r /dev/tty && -w /dev/tty ]] || die "No interactive terminal available. Set STEAM_DRIVE_UUID explicitly."

  local candidates=()
  local line
  local index=1
  local answer

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    candidates+=("$line")
  done < <(lsblk -r -p -n -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT,TYPE | awk '
    $7 == "part" && $5 != "" && $3 ~ /^(ext4|btrfs|xfs|ntfs|exfat|vfat)$/ {
      print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6
    }
  ')

  ((${#candidates[@]})) || die "No mountable partitions with UUIDs found. Check with: lsblk -f"

  printf '\nAvailable partitions:\n' >/dev/tty
  for line in "${candidates[@]}"; do
    local name=""
    local size=""
    local fstype=""
    local label=""
    local uuid=""
    local mountpoint=""

    IFS=$'\t' read -r name size fstype label uuid mountpoint <<<"$line"
    printf ' %2d) %-22s %-8s %-7s label=%-16s uuid=%s mounted=%s\n' \
      "$index" "$name" "$size" "$fstype" "$label" "$uuid" "$mountpoint" >/dev/tty
    index=$((index + 1))
  done

  while true; do
    printf '\nChoose the Steam drive partition number: ' >/dev/tty
    IFS= read -r answer </dev/tty
    if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#candidates[@]})); then
      local name=""
      local size=""
      local fstype=""
      local label=""
      local uuid=""
      local mountpoint=""

      IFS=$'\t' read -r name size fstype label uuid mountpoint <<<"${candidates[$((answer - 1))]}"
      STEAM_DRIVE_UUID="$uuid"
      if [[ -n "$fstype" ]]; then
        STEAM_DRIVE_FSTYPE="$fstype"
      fi
      log "Selected $name UUID=$STEAM_DRIVE_UUID filesystem=$STEAM_DRIVE_FSTYPE."
      return 0
    fi
    printf 'Invalid selection.\n' >/dev/tty
  done
}

validate_inputs() {
  [[ -n "$STEAM_DRIVE_UUID" ]] || die "STEAM_DRIVE_UUID is empty."

  case "$STEAM_DRIVE_MOUNT" in
    /mnt/*) ;;
    *) die "Refusing mountpoint outside /mnt: $STEAM_DRIVE_MOUNT" ;;
  esac

  if ! blkid -U "$STEAM_DRIVE_UUID" >/dev/null 2>&1; then
    die "No block device found for UUID=$STEAM_DRIVE_UUID. Check with: lsblk -f"
  fi
}

write_fstab_entry() {
  local tmp
  local entry
  tmp="$(mktemp)"
  entry="UUID=$STEAM_DRIVE_UUID $STEAM_DRIVE_MOUNT $STEAM_DRIVE_FSTYPE $STEAM_DRIVE_OPTIONS 0 2"

  log "Backing up /etc/fstab to $FSTAB_BACKUP."
  run_sudo cp -a /etc/fstab "$FSTAB_BACKUP"

  awk -v mountpoint="$STEAM_DRIVE_MOUNT" -v entry="$entry" '
    $1 !~ /^#/ && $2 == mountpoint {
      if (!written) {
        print entry
        written = 1
      }
      next
    }
    { print }
    END {
      if (!written) print entry
    }
  ' /etc/fstab >"$tmp"

  run_sudo install -m 0644 "$tmp" /etc/fstab
  rm -f "$tmp"
  log "Configured fstab entry: $entry"
}

mount_steam_drive() {
  run_sudo install -d -m 0755 "$STEAM_DRIVE_MOUNT"
  run_sudo systemctl daemon-reload

  if findmnt --target "$STEAM_DRIVE_MOUNT" >/dev/null 2>&1; then
    log "$STEAM_DRIVE_MOUNT is already mounted."
  else
    log "Mounting $STEAM_DRIVE_MOUNT."
    run_sudo mount "$STEAM_DRIVE_MOUNT"
  fi

  findmnt --target "$STEAM_DRIVE_MOUNT" >/dev/null 2>&1 || die "$STEAM_DRIVE_MOUNT is not mounted after mount attempt."
  log "Steam drive is mounted at $STEAM_DRIVE_MOUNT."
}

main() {
  require_normal_user
  choose_steam_drive_uuid
  validate_inputs
  write_fstab_entry
  mount_steam_drive
}

main "$@"
