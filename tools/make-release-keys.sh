#!/bin/bash
# Create Ladrok TV release signing keys (replacing AOSP's public test keys), in WSL:
#   bash tools/make-release-keys.sh [target_files.zip]
# Writes ~/ladrok-keys/release/ (override with KEYS=). Existing keys are never overwritten,
# so re-running only adds keys that are missing (e.g. for a new APEX).
#  - <role>.x509.pem + <role>.pk8 for each APK signing role (releasekey, platform, ...)
#  - apex/<name>.pem (RSA-4096 payload key) + apex/<name>.x509.pem/.pk8 (container key)
#    for every APEX listed in the target files' META/apexkeys.txt
# BACK THESE UP (D:\dev\drot\keys\ is gitignored). Losing them means devices can only be
# moved to new keys by a reflash; leaking them lets anyone ship "system" apps for Ladrok TV.
set -euo pipefail

KEYS=${KEYS:-$HOME/ladrok-keys/release}
TF=${1:-}
SUBJ_BASE='/C=US/O=Ladrok TV'
mkdir -p "$KEYS/apex"
chmod 700 "$HOME/ladrok-keys" "$KEYS" "$KEYS/apex"

# x509 certificate + PKCS#8 DER private key, the format signapk / apksigner expect
make_cert_key() { # <path-without-ext> <cn>
  local p=$1 cn=${2:0:64}   # X.509 limits the Common Name to 64 characters
  [ -f "$p.pk8" ] && return 0
  openssl genrsa -out "$p.tmp.key" 4096 2>/dev/null
  openssl req -new -x509 -sha256 -key "$p.tmp.key" -out "$p.x509.pem" -days 10950 \
    -subj "$SUBJ_BASE/CN=$cn"
  openssl pkcs8 -in "$p.tmp.key" -topk8 -outform DER -out "$p.pk8" -nocrypt
  rm -f "$p.tmp.key"
  chmod 600 "$p.pk8"
  echo "  created $(basename "$p")"
}

echo "APK signing keys in $KEYS"
for role in releasekey platform shared media networkstack sdk_sandbox bluetooth nfc; do
  make_cert_key "$KEYS/$role" "Ladrok TV $role"
done

if [ -n "$TF" ]; then
  echo "APEX keys for the APEXes in $TF"
  for apex in $(unzip -p "$TF" META/apexkeys.txt | sed -E 's/^name="([^"]*)\.apex".*/\1/' | grep -v '^name='); do
    if [ ! -f "$KEYS/apex/$apex.pem" ]; then
      openssl genrsa -out "$KEYS/apex/$apex.pem" 4096 2>/dev/null
      chmod 600 "$KEYS/apex/$apex.pem"
    fi
    make_cert_key "$KEYS/apex/$apex" "Ladrok TV $apex"
  done
fi
echo "Keys: $(ls "$KEYS"/*.pk8 | wc -l) APK roles, $(ls "$KEYS"/apex/*.pem 2>/dev/null | grep -vc x509) APEX payload keys"
