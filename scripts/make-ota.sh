#!/bin/bash
# Build one Ladrok TV release variant: release-signed target files, the A/B OTA package with
# the update-<variant>.json the on-device updater reads, and optionally the SD-card image.
# Run in WSL as the build user, after sync.sh + apply-patches.sh:
#   VARIANT=userdebug|user bash scripts/make-ota.sh [--image] [--incremental-from <signed target_files.zip>]
# Both variants of one release share the version (BUILD_NUMBER), so set it once:
#   export BUILD_NUMBER=$(date +%Y%m%d.%H%M)
#   VARIANT=userdebug bash scripts/make-ota.sh --image; VARIANT=user bash scripts/make-ota.sh --image
# user builds go to their own output dir (OUT_DIR=out_user), so alternating variants doesn't
# rebuild the tree each time.
#
# Output in ~/ladrok-tv-releases/<version>/ (and <repo>/releases/<version>/, without the target files):
#   ladrok-tv-<version>-<variant>-ota.zip   OTA package (attach to the GitHub release)
#   update-<variant>.json                   what the updater reads (attach)
#   ladrok-tv-<version>-<variant>.img.xz    card image for fresh installs (--image; attach)
#   target_files-<variant>.zip              signed; keep it, it is the base for incremental OTAs
#
# Keys (never in git; back them up, see D:\dev\drot\keys):
#   OTA payload key  $OTA_KEY (default ~/ladrok-keys/ota); its certificate must equal
#                    device/brcm/rpi5/security/ota.x509.pem or devices refuse the update.
#   release keys     $KEYS (default ~/ladrok-keys/release), via tools/sign-target-files.sh.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
KEY=${OTA_KEY:-$HOME/ladrok-keys/ota}
VARIANT=${VARIANT:-userdebug}
case $VARIANT in user|userdebug) ;; *) echo "VARIANT must be user or userdebug"; exit 2 ;; esac
IMAGE=0 INCR=()
while [ $# -gt 0 ]; do
  case $1 in
    --image) IMAGE=1 ;;
    --incremental-from) INCR=(-i "$2"); shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done
[ -f "$KEY.pk8" ] || { echo "missing signing key $KEY.pk8"; exit 1; }

export AOSP=${AOSP:-$HOME/aosp-rpi}
cd "$AOSP"
cmp -s "$KEY.x509.pem" device/brcm/rpi5/security/ota.x509.pem ||
  { echo "$KEY.x509.pem differs from the certificate in the device tree"; exit 1; }
LAYOUT=$(sed -n 's:.*<integer name="layout_version">\([0-9]*\)</integer>.*:\1:p' \
  device/brcm/rpi5/LadrokUpdater/res/values/config.xml)
[ -n "$LAYOUT" ] || { echo "cannot read layout_version from LadrokUpdater config.xml"; exit 1; }
# Newest Ladrok Launcher and Ladrok Store releases (LAUNCHER_VERSION / STORE_VERSION=vX.Y.Z pin
# one, e.g. to rebuild an old release)
bash "$REPO/scripts/fetch-prebuilts.sh"
LAUNCHER=$(cat device/brcm/rpi5/LadrokLauncher/VERSION)
STORE=$(cat device/brcm/rpi5/LadrokStore/VERSION)

# envsetup's shell functions (lunch, make) read unset variables: no `set -u` from here on
set +u
export BUILD_NUMBER=${BUILD_NUMBER:-$(date +%Y%m%d.%H%M)}   # the version (ro.build.version.incremental)
if [ "$VARIANT" = user ]; then export OUT_DIR=out_user; fi
source build/envsetup.sh >/dev/null
lunch aosp_rpi5_tv-cp2a-$VARIANT >/dev/null
make target-files-package otatools -j$(nproc)
HOSTBIN=$AOSP/${OUT_DIR:-out}/host/linux-x86/bin
# The prebuilts in the image must carry their own signature (presigned, never re-signed)
for apk in app/LadrokLauncher/LadrokLauncher.apk priv-app/LadrokStore/LadrokStore.apk; do
  bash "$REPO/scripts/fetch-prebuilts.sh" --check "$ANDROID_PRODUCT_OUT/system/system_ext/$apk"
done

TF=$(ls -t "$ANDROID_PRODUCT_OUT"/obj/PACKAGING/target_files_intermediates/*-target_files*.zip | head -1)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
bash "$REPO/tools/sign-target-files.sh" "$TF" "$W/target_files.zip"
"$HOSTBIN/ota_from_target_files" -k "$KEY" "${INCR[@]}" "$W/target_files.zip" "$W/ota.zip"

python3 - "$W/ota.zip" "$W" "$VARIANT" "$LAYOUT" "$LAUNCHER" "$STORE" <<'EOF'
import hashlib, json, os, struct, sys, zipfile
ota, work, variant, layout = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
launcher, store = sys.argv[5], sys.argv[6]
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
version = meta["post-build-incremental"]
name = f"ladrok-tv-{version}-{variant}-ota.zip"
cfg = {
    "version": version,
    "variant": variant,
    "layout": layout,
    "launcher": launcher,
    "store": store,
    "fingerprint": meta.get("post-build", ""),
    "timestamp": int(meta["post-timestamp"]),
    "incremental_from": meta.get("pre-build", None),
    "file": name,
    "size": os.path.getsize(ota),
    "sha256": sha.hexdigest(),
    "payload_offset": offset,
    "payload_size": info.file_size,
    "payload_properties": props,
}
os.rename(ota, os.path.join(work, name))
with open(os.path.join(work, f"update-{variant}.json"), "w") as f:
    json.dump(cfg, f, indent=2)
with open(os.path.join(work, "version"), "w") as f:
    f.write(version)
print(json.dumps(cfg, indent=2))
EOF

VER=$(cat "$W/version")
R=$HOME/ladrok-tv-releases/$VER
mkdir -p "$R" "$REPO/releases/$VER"
cp "$W"/ladrok-tv-*-ota.zip "$W/update-$VARIANT.json" "$R/"
cp "$W/target_files.zip" "$R/target_files-$VARIANT.zip"
cp "$W"/ladrok-tv-*-ota.zip "$W/update-$VARIANT.json" "$REPO/releases/$VER/"

if [ $IMAGE = 1 ]; then
  # Card image from the same signed images the OTA carries
  mkdir -p "$W/img"
  unzip -q -o "$W/target_files.zip" IMAGES/system.img IMAGES/vendor.img 'RADIO/rpiboot.img' -d "$W/img"
  for p in system vendor; do
    f=$W/img/IMAGES/$p.img
    if [ "$(od -An -tx4 -N4 "$f" | tr -d ' ')" = ed26ff3a ]; then   # Android sparse image
      "$HOSTBIN/simg2img" "$f" "$W/img/$p.img"
    else
      mv "$f" "$W/img/$p.img"
    fi
  done
  mv "$W/img/RADIO/rpiboot.img" "$W/img/boot.img"
  IMG=$W/img/ladrok-tv-$VER-$VARIANT.img
  OUT=$W/img bash "$REPO/scripts/mkimg-ab.sh" "$IMG"
  xz -T0 -6 -f "$IMG"
  (cd "$W/img" && sha256sum "$(basename "$IMG").xz" > "$(basename "$IMG").xz.sha256")
  cp "$IMG.xz" "$IMG.xz.sha256" "$R/"
  cp "$IMG.xz" "$IMG.xz.sha256" "$REPO/releases/$VER/"
fi
echo "RELEASE DONE ($VARIANT): $R"
ls -l "$R"
