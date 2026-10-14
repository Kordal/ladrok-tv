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
