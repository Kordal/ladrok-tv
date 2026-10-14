#!/bin/bash
# Create a flashable Ladrok TV A/B SD-card image (GPT) from boot.img, system.img and vendor.img.
# Runs as a normal user (sgdisk/mtools/dd on a plain file, no loop devices).
#
#   p1  bootsel     64M  FAT32, only autoboot.txt (which rpiboot partition the firmware boots)
#   p2  rpiboot_a  128M  FAT32 = boot.img (kernel, dtbs, ramdisk, config.txt, cmdline_*.txt)
#   p3  rpiboot_b  128M  empty until the first OTA
#   p4  misc         1M  slot metadata (libboot_control)
#   p5  system_a     3G  system.img
#   p6  system_b     3G  empty
#   p7  vendor_a   384M  vendor.img
#   p8  vendor_b   384M  empty
#   p9  metadata    16M  ext4
#   p10 userdata     1G  ext4; rpi_resize_data grows it to the end of the card on first boot
#
# The firmware's boot_partition numbers (autoboot.txt, config.txt filters) are these GPT
# entry numbers, so keep the order in sync with device/brcm/rpi5/boot/config.txt and the
# boot control HAL (SlotPartition()).
set -euo pipefail

OUT=${OUT:-$HOME/aosp-rpi/out/target/product/rpi5}
IMG=${1:-$OUT/ladrok-tv-$(date +%Y%m%d).img}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

for f in boot system vendor; do
  [ -f "$OUT/$f.img" ] || { echo "missing $OUT/$f.img"; exit 1; }
done

#        name       MiB   GPT type
PARTS=( "bootsel    64    0700"
        "rpiboot_a  128   0700"
        "rpiboot_b  128   0700"
        "misc       1     8300"
        "system_a   3072  8300"
        "system_b   3072  8300"
        "vendor_a   384   8300"
        "vendor_b   384   8300"
        "metadata   16    8300"
        "userdata   1024  8300" )

total=2   # MiB: 1 for the primary GPT + alignment, 1 for the backup GPT
args=()
n=1
for p in "${PARTS[@]}"; do
  read -r name mib type <<<"$p"
  total=$((total + mib))
  args+=(-n "$n:0:+${mib}M" -t "$n:$type" -c "$n:$name")
  n=$((n + 1))
done

rm -f "$IMG"
truncate -s "${total}M" "$IMG"
sgdisk -Z "$IMG" >/dev/null 2>&1 || true
sgdisk -a 2048 "${args[@]}" "$IMG" >/dev/null

start_of() { sgdisk -i "$1" "$IMG" | awk '/^First sector/ {print $3}'; }
size_of()  { sgdisk -i "$1" "$IMG" | awk '/^Partition size/ {print $3}'; }
put() { # put <partno> <file>: file must be exactly the partition size
  local s=$(start_of "$1") sz=$(size_of "$1") fsz=$(stat -c %s "$2")
  [ "$fsz" = $((sz * 512)) ] || { echo "$2 is $fsz bytes, partition $1 is $((sz * 512))"; exit 1; }
  dd if="$2" of="$IMG" bs=4M seek=$((s * 512)) oflag=seek_bytes conv=notrunc,sparse status=none
  echo "  p$1 <- $(basename "$2")"
}

# bootsel: a fixed 512-byte autoboot.txt, rewritten in place by the HAL (see autoboot.c)
truncate -s 64M "$W/bootsel.img"
mkfs.fat -F 32 -n BOOTSEL "$W/bootsel.img" >/dev/null
printf '%s\n' "# Written by the boot control HAL (android.hardware.boot-service.rpi)." \
  "# Must stay exactly 512 bytes: it is rewritten in place." \
  "[all]" "tryboot_a_b=1" "boot_partition=2" "[tryboot]" "boot_partition=3" > "$W/autoboot.txt"
len=$(stat -c %s "$W/autoboot.txt")
{ cat "$W/autoboot.txt"; printf '#'; head -c $((512 - len - 2)) /dev/zero | tr '\0' ' '; printf '\n'; } > "$W/ab"
[ "$(stat -c %s "$W/ab")" = 512 ] || { echo "autoboot.txt is not 512 bytes"; exit 1; }
mcopy -i "$W/bootsel.img" "$W/ab" ::autoboot.txt

truncate -s 16M "$W/metadata.img";   mkfs.ext4 -q -I 512 -L metadata "$W/metadata.img"
truncate -s 1024M "$W/userdata.img"; mkfs.ext4 -q -I 512 -L userdata "$W/userdata.img"

echo "Writing $IMG (${total} MiB)"
put 1 "$W/bootsel.img"
put 2 "$OUT/boot.img"
put 5 "$OUT/system.img"
put 7 "$OUT/vendor.img"
put 9 "$W/metadata.img"
put 10 "$W/userdata.img"
sgdisk -v "$IMG" | grep -iE 'no problems|problem' || true
echo "Done: $IMG"
