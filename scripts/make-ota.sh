#!/bin/bash
# Build a signed A/B OTA package plus the update.json the on-device updater reads.
# Run in WSL as the build user, after sync.sh + apply-patches.sh:
#   bash scripts/make-ota.sh [--incremental-from <old target_files.zip>]
# Output: ~/ladrok-tv-releases/<build timestamp>/{ladrok-tv-ota-*.zip,update.json,target_files.zip}
# and a copy in <repo>/releases/ (gitignored). Keep target_files.zip: it is the
# source for future incremental packages. Attach the zip and update.json to a GitHub release.
#
# Signing key: $OTA_KEY.pk8 / $OTA_KEY.x509.pem (default ~/ladrok-keys/ota). Its certificate
# must be the one in device/brcm/rpi5/security/ota.x509.pem, or devices reject the update.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
KEY=${OTA_KEY:-$HOME/ladrok-keys/ota}
INCR=()
if [ "${1:-}" = --incremental-from ]; then INCR=(-i "$2"); fi
[ -f "$KEY.pk8" ] || { echo "missing signing key $KEY.pk8"; exit 1; }

cd ${AOSP:-$HOME/aosp-rpi}
cmp -s "$KEY.x509.pem" device/brcm/rpi5/security/ota.x509.pem ||
  { echo "$KEY.x509.pem differs from the certificate in the device tree"; exit 1; }
# envsetup's shell functions (lunch, make) read unset variables: no `set -u` from here on
set +u
export BUILD_NUMBER=${BUILD_NUMBER:-$(date +%Y%m%d.%H%M)}   # shown as the version (ro.build.version.incremental)
source build/envsetup.sh >/dev/null
lunch aosp_rpi5_tv-cp2a-userdebug >/dev/null
make target-files-package otatools -j$(nproc)

TF=$(ls -t "$ANDROID_PRODUCT_OUT"/obj/PACKAGING/target_files_intermediates/*-target_files*.zip | head -1)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
out/host/linux-x86/bin/ota_from_target_files -k "$KEY" "${INCR[@]}" "$TF" "$W/ota.zip"

python3 - "$W/ota.zip" "$W" <<'EOF'
import hashlib, json, os, struct, sys, zipfile
ota, work = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(ota) as z:
    meta = dict(l.split("=", 1) for l in z.read("META-INF/com/android/metadata").decode().splitlines() if "=" in l)
    props = z.read("payload_properties.txt").decode().split()
    info = z.getinfo("payload.bin")
    assert info.compress_type == zipfile.ZIP_STORED, "payload.bin must be stored"
with open(ota, "rb") as f:
    f.seek(info.header_offset)
    hdr = f.read(30)
    name_len, extra_len = struct.unpack("<HH", hdr[26:30])
    offset = info.header_offset + 30 + name_len + extra_len
    f.seek(0)
    sha = hashlib.sha256()
    for chunk in iter(lambda: f.read(1 << 20), b""):
        sha.update(chunk)
ts = int(meta["post-timestamp"])
name = f"ladrok-tv-ota-{ts}.zip"
cfg = {
    "version": meta.get("post-build-incremental", str(ts)),
    "fingerprint": meta.get("post-build", ""),
    "timestamp": ts,
    "incremental_from": meta.get("pre-build", None),
    "file": name,
    "size": os.path.getsize(ota),
    "sha256": sha.hexdigest(),
    "payload_offset": offset,
    "payload_size": info.file_size,
    "payload_properties": props,
}
os.rename(ota, os.path.join(work, name))
with open(os.path.join(work, "update.json"), "w") as f:
    json.dump(cfg, f, indent=2)
print(json.dumps(cfg, indent=2))
EOF

ts=$(python3 -c "import json;print(json.load(open('$W/update.json'))['timestamp'])")
R=$HOME/ladrok-tv-releases/$ts
mkdir -p "$R" "$REPO/releases/$ts"
cp "$W"/ladrok-tv-ota-*.zip "$W/update.json" "$R/"
cp "$TF" "$R/target_files.zip"
cp "$W"/ladrok-tv-ota-*.zip "$W/update.json" "$REPO/releases/$ts/"
echo "OTA DONE: $R"
