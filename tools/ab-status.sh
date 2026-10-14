# A/B status on the Pi: adb push tools/ab-status.sh /data/local/tmp/ && adb shell sh /data/local/tmp/ab-status.sh
# (as root: rpi_tryboot needs /dev/vcio and the bootsel partition)
echo "slot=$(getprop ro.boot.slot_suffix) build=$(getprop ro.build.date.utc)"
/vendor/bin/rpi_tryboot status
logcat -d -b all | grep -E 'boot-service.rpi' | grep -vE 'libfstab|Thread Pool' | tail -6
logcat -d -s update_engine:* | grep -E 'Marking booted slot|booted into|Update successfully|rollback|kPayload|Error' | tail -4
