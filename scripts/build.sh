#!/bin/bash
# Build Ladrok TV and create a flashable A/B SD-card image (scripts/mkimg-ab.sh),
# copied to the repo root. Flashing it wipes the card.
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd ${AOSP:-$HOME/aosp-rpi}
export BUILD_NUMBER=${BUILD_NUMBER:-$(date +%Y%m%d.%H%M)}   # shown as the version (ro.build.version.incremental)
source build/envsetup.sh
lunch aosp_rpi5_tv-cp2a-userdebug
make bootimage systemimage vendorimage -j$(nproc)
IMG=${ANDROID_PRODUCT_OUT}/ladrok-tv-$(date +%Y%m%d).img
bash "$REPO/scripts/mkimg-ab.sh" "$IMG"
cp -v "$IMG" "$REPO/"
echo "BUILD DONE"
