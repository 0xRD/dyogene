#!/bin/zsh
# Builds and signs build/Dyogene.app (app + `dyogene` CLI in Contents/Helpers). The designated
# requirement pins the bundle id and the certificate, so it does not change between builds and the
# Full Disk Access grant stays.
#
# DYOGENE_SIGN_IDENTITY=- signs ad hoc (CI only: the Full Disk Access grant will not survive
# rebuilds). DYOGENE_KEYCHAIN selects a keychain.
set -euo pipefail
cd "${0:A:h}/.."

bundle_id="io.github.0xrd.dyogene"
identity="${DYOGENE_SIGN_IDENTITY:-Dyogene Local Signing}"
keychain="${DYOGENE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
app=build/Dyogene.app

sign_args=()
if [[ "$identity" != "-" ]]; then
    fingerprint=$(security find-certificate -c "$identity" -Z "$keychain" 2>/dev/null \
        | awk '/^SHA-1 hash:/ { print $3; exit }')
    if [[ -z "$fingerprint" ]]; then
        print -u2 "build-app: no '$identity' certificate. Run scripts/make-cert.sh first, or DYOGENE_SIGN_IDENTITY=-."
        exit 1
    fi
    identity="$fingerprint"
    sign_args=(--keychain "$keychain" --timestamp=none)
    app_requirement="=designated => identifier \"$bundle_id\" and certificate leaf = H\"$fingerprint\""
    cli_requirement="=designated => identifier \"$bundle_id.cli\" and certificate leaf = H\"$fingerprint\""
fi

swift build -c release
bin="$(swift build -c release --show-bin-path)"

[[ -f Resources/Dyogene.icns ]] || scripts/make-icns.sh

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
cp "$bin/DyogeneApp" "$app/Contents/MacOS/DyogeneApp"
cp "$bin/dyogene" "$app/Contents/Helpers/dyogene"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/Dyogene.icns "$app/Contents/Resources/Dyogene.icns"

if [[ "$identity" == "-" ]]; then
    codesign --force --sign - --options runtime --identifier "$bundle_id.cli" "$app/Contents/Helpers/dyogene"
    codesign --force --sign - --options runtime --identifier "$bundle_id" "$app"
else
    codesign --force --sign "$identity" --options runtime --identifier "$bundle_id.cli" \
        "${sign_args[@]}" --requirements "$cli_requirement" "$app/Contents/Helpers/dyogene"
    codesign --force --sign "$identity" --options runtime --identifier "$bundle_id" \
        "${sign_args[@]}" --requirements "$app_requirement" "$app"
fi

codesign --verify --strict --deep "$app"
print "build-app: built $app"
