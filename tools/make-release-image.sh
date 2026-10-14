#!/bin/bash
# Card image for a release: mkimg-ab.sh from the current build output, then xz for download
# (Raspberry Pi Imager writes .img.xz directly). Output in <repo>/releases/<ts>/.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TS=${1:?release timestamp dir name}
OUT=${OUT:-$HOME/aosp-rpi/out/target/product/rpi5}
VER=$(sed -n 's/^ro.build.version.incremental=//p' "$OUT/system/build.prop")
IMG=$OUT/ladrok-tv-$VER.img
bash "$REPO/scripts/mkimg-ab.sh" "$IMG"
xz -T0 -6 -k -f "$IMG"
mkdir -p "$REPO/releases/$TS"
cp "$IMG.xz" "$REPO/releases/$TS/"
sha256sum "$IMG.xz" | tee "$REPO/releases/$TS/$(basename "$IMG").xz.sha256"
ls -l "$REPO/releases/$TS/"
