#!/bin/bash
# Build only boot/system/vendor .img (no SD-card image, no OTA), e.g. to test a change.
# Run from WSL: bash scripts/build-images.sh   (after sync.sh + apply-patches.sh)
# For a release use scripts/make-ota.sh; for a card image scripts/build.sh.
set -e
cd ${AOSP:-$HOME/aosp-rpi}
export BUILD_NUMBER=${BUILD_NUMBER:-$(date +%Y%m%d.%H%M)}   # shown as the version (ro.build.version.incremental)
source build/envsetup.sh
lunch aosp_rpi5_tv-cp2a-userdebug
make bootimage systemimage vendorimage -j$(nproc)
ls -l ${ANDROID_PRODUCT_OUT}/{boot,system,vendor}.img
echo "IMAGES DONE"
