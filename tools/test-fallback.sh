# Rollback test (root): break slot A's cmdline, arm a one-shot tryboot into A, reboot.
# Expected: A fails to mount its system, init reboots, the firmware boots slot B again.
# Afterwards run: sh test-fallback.sh restore
set -e
T=/data/local/tmp
mkdir -p $T/ra
mount -t vfat /dev/block/by-name/rpiboot_a $T/ra
if [ "$1" = restore ]; then
  cp $T/cmdline_a.txt.good $T/ra/cmdline_a.txt
  grep -o 'slot_suffix=_.' $T/ra/cmdline_a.txt
  sync; umount $T/ra
  exit 0
fi
[ -f $T/cmdline_a.txt.good ] || cp $T/ra/cmdline_a.txt $T/cmdline_a.txt.good
sed 's/slot_suffix=_a/slot_suffix=_x/' $T/cmdline_a.txt.good > $T/ra/cmdline_a.txt
grep -o 'slot_suffix=_.' $T/ra/cmdline_a.txt
sync; umount $T/ra
/vendor/bin/rpi_tryboot set
