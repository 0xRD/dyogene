#!/bin/zsh
# Builds, signs, checks and publishes a GitHub release of Dyogène, then prints what the Homebrew
# cask in 0xRD/homebrew-tap needs: the version and the archive's SHA-256.
#
# Usage: scripts/release.sh    (the version comes from Resources/Info.plist)
set -euo pipefail
cd "${0:A:h}/.."

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
tag="v$version"
archive="build/Dyogene-$version-macOS.zip"

if [[ -n "$(git status --porcelain)" ]]; then
    print -u2 "release: the working tree has uncommitted changes"
    exit 1
fi
# A release is cut from what is on GitHub's main, never from a branch or a stale clone.
git fetch --quiet --tags origin main
if [[ "$(git rev-parse --abbrev-ref HEAD)" != "main" || "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
    print -u2 "release: check out main and bring it level with origin/main first"
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    print -u2 "release: $tag already exists; bump CFBundleShortVersionString first"
    exit 1
fi

scripts/check.sh
scripts/build-app.sh

# The bundle must run, and its CLI must answer, before anything is published.
build/Dyogene.app/Contents/Helpers/dyogene summary --demo >/dev/null
codesign --verify --strict --deep build/Dyogene.app

rm -f "$archive"
# ditto keeps the signature and extended attributes intact, which zip does not.
ditto -c -k --sequesterRsrc --keepParent build/Dyogene.app "$archive"
sha=$(shasum -a 256 "$archive" | awk '{ print $1 }')

git tag -a "$tag" -m "Dyogène $version"
git push origin "$tag"
gh release create "$tag" "$archive" --title "Dyogène $version" --notes "$(cat <<NOTES
Install with Homebrew: \`brew install --cask 0xrd/tap/dyogene\`, or download the archive below.

Not notarized: on first launch, allow it in System Settings, Privacy & Security, Open Anyway.
Full Disk Access is optional: without it, folders macOS protects are skipped and counted as not seen.
No network access, metadata only. See the README and SECURITY.md.

SHA-256 of $(basename "$archive"): $sha
NOTES
)"

print "release: $tag published"
print "cask: version \"$version\""
print "cask: sha256 \"$sha\""
