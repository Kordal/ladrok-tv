#!/bin/bash
# Re-sign a target-files package with the Ladrok TV release keys (instead of AOSP's public
# test keys) and rebuild its images. In WSL, after a build (needs the host otatools):
#   bash tools/sign-target-files.sh <in-target_files.zip> <out-signed-target_files.zip>
# Keys: ~/ladrok-keys/release (KEYS=...), created by tools/make-release-keys.sh; any APEX
# without a key yet gets one first.
#  - APKs: -d maps build/make/target/product/security/<role> to $KEYS/<role>
#    (testkey -> releasekey, platform, shared, media, networkstack, ...).
#  - APEXes: container and payload key per APEX (-e / --extra_apex_payload_key).
# The OTA key is separate (~/ladrok-keys/ota, see scripts/make-ota.sh).
set -euo pipefail

IN=$1 OUT=$2
REPO=$(cd "$(dirname "$0")/.." && pwd)
AOSP=${AOSP:-$HOME/aosp-rpi}
KEYS=${KEYS:-$HOME/ladrok-keys/release}

bash "$REPO/tools/make-release-keys.sh" "$IN"

args=(-d "$KEYS")
for apex in $(unzip -p "$IN" META/apexkeys.txt | sed -E 's/^name="([^"]*)\.apex".*/\1/'); do
  args+=(-e "$apex.apex=$KEYS/apex/$apex" --extra_apex_payload_key "$apex.apex=$KEYS/apex/$apex.pem")
done

cd "$AOSP"
HOSTBIN=$AOSP/${OUT_DIR:-out}/host/linux-x86/bin   # user builds use OUT_DIR=out_user
PATH=$HOSTBIN:$PATH "$HOSTBIN/sign_target_files_apks" "${args[@]}" "$IN" "$OUT"

# Sanity check: platform-signed APKs in the signed package must carry our platform certificate
# (META/apkcerts.txt is not a reliable check: it keeps the build's original key paths).
want=$(openssl x509 -in "$KEYS/platform.x509.pem" -outform DER | sha256sum | cut -d' ' -f1)
JDK=$(ls -d "$AOSP"/prebuilts/jdk/jdk2*/linux-x86/bin | sort -V | tail -1)   # apksigner needs java
export PATH=$JDK:$PATH
T=$(mktemp -d)
unzip -q -o "$OUT" SYSTEM/framework/framework-res.apk \
  'SYSTEM/system_ext/priv-app/LadrokUpdater/LadrokUpdater.apk' -d "$T"
for apk in "$T"/SYSTEM/framework/framework-res.apk "$T"/SYSTEM/system_ext/priv-app/LadrokUpdater/LadrokUpdater.apk; do
  got=$("$HOSTBIN/apksigner" verify --print-certs "$apk" 2>/dev/null |
    sed -n 's/^.*[Ss]igner.* certificate SHA-256 digest: //p' | head -1)
  [ "$got" = "$want" ] || { rm -rf "$T"; echo "ERROR: $(basename "$apk") is not signed with our platform key ($got)"; exit 1; }
done
rm -rf "$T"
echo "signed OK: $OUT (platform cert sha256 ${want:0:16}...)"
