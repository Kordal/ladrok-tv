#!/bin/bash
# Export local (uncommitted) changes from the AOSP tree into patches/ in this repo.
# Run from WSL: bash scripts/export-patches.sh
set -e
SRC=${SRC:-$HOME/aosp-rpi}
OUT=$(cd "$(dirname "$0")/.." && pwd)/patches
mkdir -p "$OUT"
# project dir in the AOSP tree -> patch file name
declare -A PROJECTS=(
  [device/brcm/rpi5]=device_brcm_rpi5.patch
  [device/google/atv]=device_google_atv.patch
  [build/make]=build_make.patch
  [system/sepolicy]=system_sepolicy.patch
)
for p in "${!PROJECTS[@]}"; do
  # intent-to-add so new (untracked) files show up in the diff too
  git -C "$SRC/$p" add -N .
  git -C "$SRC/$p" diff --binary > "$OUT/${PROJECTS[$p]}"
  echo "$p -> patches/${PROJECTS[$p]} ($(wc -l < "$OUT/${PROJECTS[$p]}") lines)"
done
