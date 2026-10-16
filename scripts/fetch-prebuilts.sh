#!/bin/bash
# Ladrok's own apps that are built in their own repos (Gradle) and go into the image as prebuilts:
# put the newest release APK of each into the AOSP tree (device/brcm/rpi5/<Name>/<Name>.apk).
#   bash scripts/fetch-prebuilts.sh                   all apps, newest release each
#   LAUNCHER_VERSION=v0.2.0 STORE_VERSION=v0.1.1 ...  pin versions (e.g. to rebuild an old release)
#   bash scripts/fetch-prebuilts.sh --check APK       only check APK's signing certificate
# Called by apply-patches.sh and make-ota.sh. Trust comes from the signing certificate, pinned
# below: any release signed with the Ladrok app key is accepted, nothing else is. The release's
# .sha256 file only catches broken downloads. The tag that was fetched is written to VERSION
# next to the APK; make-ota.sh records it in update-<variant>.json.
set -euo pipefail

# Name, GitHub repo, version-pin variable
APPS=(
  "LadrokLauncher Kordal/ladrok-start LAUNCHER_VERSION"   # the home screen
  "LadrokStore Kordal/ladrok-store STORE_VERSION"         # the app store
)
# SHA-256 of the signing certificate both apps share (CN=Ladrok Launcher). Change only if that key
# is rotated; Ladrok Store's catalog (catalog/apps.yaml in ladrok-store) pins the same value for
# updates between OS releases.
CERT_SHA256=00d9faeb7a77c0d3edcc6f9ba807b7061faa49fb6c60daf808dc79c9ee6ac43e
SRC=${SRC:-${AOSP:-$HOME/aosp-rpi}}

# apksigner verifies the signature, then prints the certificate digest. It is a host tool of
# the AOSP build, so on a fresh tree (no out/ yet) the check is left to make-ota.sh.
apksigner() {
  local bin
  for bin in "$SRC/${OUT_DIR:-out}/host/linux-x86/bin/apksigner" "$SRC/out/host/linux-x86/bin/apksigner"; do
    if [ -x "$bin" ]; then
      PATH=$(ls -d "$SRC"/prebuilts/jdk/jdk2*/linux-x86/bin | tail -1):$PATH "$bin" "$@"
      return
    fi
  done
  return 127
}
check_cert() {
  local out certs
  out=$(apksigner verify --print-certs "$1" 2>/dev/null) || {
    [ $? = 127 ] && { echo "$(basename "$1"): no apksigner yet, certificate not checked" >&2; return 0; }
    echo "$1 has no valid signature" >&2; return 1; }
  # One line per signer and scheme ("V2 Signer: ...", "Signer #1 ..."): all must be our key
  certs=$(sed -n 's/.*certificate SHA-256 digest: \([0-9a-f]*\).*/\1/p' <<<"$out" | sort -u)
  [ "$certs" = "$CERT_SHA256" ] || { echo "$1 is not signed with the Ladrok app key" >&2; return 1; }
}

if [ "${1:-}" = --check ]; then
  check_cert "$2"
  exit
fi

# Newest release with a version tag (v*) that carries <Name>.apk. Not releases/latest: a repo
# can have other releases too (ladrok-store's "Catalog"), and one of them could be the latest.
newest_tag() {
  curl -fsSL "https://api.github.com/repos/$1/releases?per_page=30" | python3 -c '
import json, re, sys
apk = sys.argv[1]
for r in json.load(sys.stdin):  # newest first
    if r["draft"] or r["prerelease"] or not re.match(r"v\d", r["tag_name"]):
        continue
    if any(a["name"] == apk for a in r["assets"]):
        print(r["tag_name"]); break
else:
    sys.exit(f"no v* release with {apk}")' "$2"
}

for app in "${APPS[@]}"; do
  read -r name repo pin <<<"$app"
  dir=$SRC/device/brcm/rpi5/$name
  tag=${!pin:-$(newest_tag "$repo" "$name.apk")}
  if [ -f "$dir/$name.apk" ] && [ "$(cat "$dir/VERSION" 2>/dev/null)" = "$tag" ]; then
    echo "$name: $tag (up to date)"
    continue
  fi
  url=https://github.com/$repo/releases/download/$tag
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/$name.apk" "$url/$name.apk"
  curl -fsSL -o "$tmp/$name.apk.sha256" "$url/$name.apk.sha256"
  want=$(awk '{print $1; exit}' "$tmp/$name.apk.sha256")
  have=$(sha256sum "$tmp/$name.apk" | awk '{print $1}')
  [ "$want" = "$have" ] || { echo "$name: $tag download is corrupt (SHA-256 mismatch)" >&2; rm -rf "$tmp"; exit 1; }
  check_cert "$tmp/$name.apk" || { rm -rf "$tmp"; exit 1; }
  mv "$tmp/$name.apk" "$dir/$name.apk"
  echo "$tag" > "$dir/VERSION"
  rm -rf "$tmp"
  echo "$name: $tag (sha256 $have)"
done
