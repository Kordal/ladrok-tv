#!/bin/bash
# Apply patches/ onto a synced AOSP tree (after scripts/sync.sh). Safe to re-run.
# Run from WSL: bash scripts/apply-patches.sh
set -e
SRC=${SRC:-$HOME/aosp-rpi}
DIR=$(cd "$(dirname "$0")/.." && pwd)/patches
declare -A PROJECTS=(
  [device/brcm/rpi5]=device_brcm_rpi5.patch
  [device/google/atv]=device_google_atv.patch
  [build/make]=build_make.patch
)
for p in "${!PROJECTS[@]}"; do
  f="$DIR/${PROJECTS[$p]}"
  [ -s "$f" ] || continue
  if git -C "$SRC/$p" apply --reverse --check "$f" 2>/dev/null; then
    echo "$p: already applied"
  else
    git -C "$SRC/$p" apply "$f" && echo "$p: applied"
  fi
done

# Prebuilt Ladrok apps, built and signed in their own repos. Each is pinned to one release:
# bump its URL and SHA256 lines together.
LAUNCHER_URL=https://github.com/Kordal/ladrok-start/releases/download/v0.2.0/LadrokLauncher.apk
LAUNCHER_SHA256=0fd64f83abc439444ea66cd7da55b459c8dd2c2553e87f1e4cbb887990860b64
STORE_URL=https://github.com/Kordal/ladrok-store/releases/download/v0.1.0/LadrokStore.apk
STORE_SHA256=8f72bad6d7e8f7ff7ae1a0a4c8d5667350ef9f3b0e749993ced2ba73742e0de3

sha() { [ -f "$1" ] && sha256sum "$1" | cut -d' ' -f1; }
# prebuilt NAME URL SHA256: download the APK to device/brcm/rpi5/NAME/NAME.apk unless it is already there.
prebuilt() {
  local apk="$SRC/device/brcm/rpi5/$1/$1.apk"
  if [ "$(sha "$apk")" != "$3" ]; then
    curl -fsSL -o "$apk.part" "$2"
    if [ "$(sha "$apk.part")" != "$3" ]; then
      echo "$1: SHA-256 mismatch for $2" >&2
      rm -f "$apk.part"; exit 1
    fi
    mv "$apk.part" "$apk"
  fi
  echo "$1: $(basename "$(dirname "$2")")"
}
prebuilt LadrokLauncher "$LAUNCHER_URL" "$LAUNCHER_SHA256"  # the home screen, github.com/Kordal/ladrok-start
prebuilt LadrokStore "$STORE_URL" "$STORE_SHA256"           # the app store, github.com/Kordal/ladrok-store
