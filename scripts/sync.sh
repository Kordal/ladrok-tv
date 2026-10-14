#!/bin/bash
# Sync AOSP 17 + raspberry-vanilla RPi device trees (shallow) into ~/aosp-rpi
set -e
export PATH=$HOME/bin:$PATH
SRC=$HOME/aosp-rpi
mkdir -p "$SRC" && cd "$SRC"

if [ ! -d .repo ]; then
  repo init -u https://android.googlesource.com/platform/manifest -b android-17.0.0_r1 --depth=1
  curl -o .repo/local_manifests/manifest_brcm_rpi.xml -L https://raw.githubusercontent.com/raspberry-vanilla/android_local_manifest/android-17.0/manifest_brcm_rpi.xml --create-dirs
  curl -o .repo/local_manifests/remove_projects.xml -L https://raw.githubusercontent.com/raspberry-vanilla/android_local_manifest/android-17.0/remove_projects.xml
fi

repo sync -c -j8 --no-tags --fail-fast --retry-fetches=5
echo "SYNC DONE"
