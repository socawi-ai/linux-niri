#!/usr/bin/env bash
set -Eeuo pipefail

STEAM_DRIVE_UUID="${STEAM_DRIVE_UUID:-b633b102-ad34-443f-969f-b59ed480fa2d}"
STEAM_DRIVE_MOUNT="${STEAM_DRIVE_MOUNT:-/mnt/steam}"
STEAM_DRIVE_FSTYPE="${STEAM_DRIVE_FSTYPE:-ext4}"
STEAM_DRIVE_OPTIONS="${STEAM_DRIVE_OPTIONS:-defaults,noatime}"

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
  validate_inputs
  write_fstab_entry
  mount_steam_drive
}

main "$@"
