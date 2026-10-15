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

# Ladrok Launcher: the home screen, built and signed in github.com/Kordal/ladrok-start.
# Pinned to one release; bump both lines together.
LAUNCHER_URL=https://github.com/Kordal/ladrok-start/releases/download/v0.2.0/LadrokLauncher.apk
LAUNCHER_SHA256=0fd64f83abc439444ea66cd7da55b459c8dd2c2553e87f1e4cbb887990860b64
apk="$SRC/device/brcm/rpi5/LadrokLauncher/LadrokLauncher.apk"
sha() { [ -f "$1" ] && sha256sum "$1" | cut -d' ' -f1; }
if [ "$(sha "$apk")" != "$LAUNCHER_SHA256" ]; then
  curl -fsSL -o "$apk.part" "$LAUNCHER_URL"
  if [ "$(sha "$apk.part")" != "$LAUNCHER_SHA256" ]; then
    echo "LadrokLauncher: SHA-256 mismatch for $LAUNCHER_URL" >&2
    rm -f "$apk.part"; exit 1
  fi
  mv "$apk.part" "$apk"
fi
echo "LadrokLauncher: $(basename "$(dirname "$LAUNCHER_URL")")"
