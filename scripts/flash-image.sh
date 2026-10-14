#!/bin/bash
# Write a full Ladrok TV SD-card image (wipes the card), after backing up the whole card.
# Normally called by scripts/flash-sd.ps1. Run as root in WSL:
#   bash flash-image.sh --image <file.img> (--device /dev/sdX | --disk-size <bytes>)
#        [--dry-run] [--no-backup] [--backup-dir DIR]
# Only accepts a card that already holds a Ladrok TV or raspberry-vanilla layout (old MBR or A/B GPT).
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
IMAGE= DEV= DISK_SIZE= DRY=0 BACKUP=1
BACKUP_DIR=$REPO/backups/$(date +%Y%m%d-%H%M%S)

while [ $# -gt 0 ]; do
  case $1 in
    --image) IMAGE=$2; shift ;;
    --device) DEV=$2; shift ;;
    --disk-size) DISK_SIZE=$2; shift ;;
    --dry-run) DRY=1 ;;
    --no-backup) BACKUP=0 ;;
    --backup-dir) BACKUP_DIR=$2; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done

die() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "must run as root (wsl -u root)"
[ -f "$IMAGE" ] || die "image $IMAGE not found"

if [ -z "$DEV" ]; then
  [ -n "$DISK_SIZE" ] || die "give --device or --disk-size"
  mapfile -t hits < <(lsblk -bdno NAME,SIZE | awk -v s="$DISK_SIZE" '$2==s {print "/dev/"$1}')
  [ ${#hits[@]} -eq 1 ] || die "expected exactly one disk of $DISK_SIZE bytes, found: ${hits[*]:-none}"
  DEV=${hits[0]}
fi
[ -b "$DEV" ] || die "$DEV is not a block device"
part() { if [[ $DEV =~ [0-9]$ ]]; then echo "${DEV}p$1"; else echo "${DEV}$1"; fi; }
blockdev --rereadpt "$DEV" 2>/dev/null || true; sleep 1

# Fingerprint: must be the Pi card, in either layout
label() { blkid -s "$1" -o value "$2" 2>/dev/null || true; }
if [ "$(label LABEL "$(part 3)")" = userdata ] && [ "$(label LABEL "$(part 7)")" = metadata ]; then
  layout="old MBR (raspberry-vanilla)"
elif [ "$(label PARTLABEL "$(part 1)")" = bootsel ] && [ "$(label PARTLABEL "$(part 10)")" = userdata ]; then
  layout="A/B GPT (Ladrok TV)"
else
  die "$DEV does not look like the Pi card (no userdata/metadata labels); refusing"
fi

isz=$(stat -c %s "$IMAGE"); dsz=$(blockdev --getsize64 "$DEV")
[ "$isz" -le "$dsz" ] || die "image ($isz bytes) is larger than the card ($dsz bytes)"
echo "Card:  $DEV, $((dsz / 1000000000)) GB, layout: $layout"
echo "Image: $IMAGE ($((isz / 1048576)) MiB)"
if [ $DRY = 1 ]; then echo "DRY RUN OK: all checks passed, nothing written."; exit 0; fi

if [ $BACKUP = 1 ]; then
  mkdir -p "$BACKUP_DIR"
  echo "Backing up the whole card to $BACKUP_DIR/card-full.img (takes a while)..."
  dd if="$DEV" of="$BACKUP_DIR/card-full.img" bs=4M conv=sparse status=progress
  sfdisk -d "$DEV" > "$BACKUP_DIR/partition-table.txt" 2>/dev/null || true
  echo "To restore: dd if=card-full.img of=<card> bs=4M conv=fsync" > "$BACKUP_DIR/RESTORE.txt"
fi

echo "Writing image..."
dd if="$IMAGE" of="$DEV" bs=4M conv=fsync status=progress
sync
echo "Verifying..."
cmp -n "$isz" "$IMAGE" "$DEV" || die "verify failed"
echo "FLASH OK: $DEV now holds $(basename "$IMAGE")"
