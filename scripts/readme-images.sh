#!/bin/zsh
# Renders the README images from DEMO DATA ONLY (made-up names and sizes), never from a real scan.
set -euo pipefail
cd "${0:A:h}/.."
[[ -x build/Dyogene.app/Contents/MacOS/DyogeneApp ]] || scripts/build-app.sh
app=build/Dyogene.app/Contents/MacOS/DyogeneApp
out=docs/images
mkdir -p "$out"

shot() {
    local name=$1; shift
    env DYOGENE_DEMO=1 DYOGENE_WINDOW_SIZE=1400x860 DYOGENE_SNAPSHOT="$PWD/$out/$name.png" "$@" "$app" >/dev/null 2>&1
    sips -Z 1600 "$out/$name.png" >/dev/null
    print "readme-images: $out/$name.png"
}

shot map-dark DYOGENE_APPEARANCE=dark DYOGENE_LENS=dust DYOGENE_HOVER=0.18,0.62
shot map-light DYOGENE_APPEARANCE=light DYOGENE_LENS=dust DYOGENE_SELECT="Movies/Wedding film master.mp4" DYOGENE_FOCUS_PARENT=1
shot map-kind DYOGENE_APPEARANCE=dark DYOGENE_LENS=kind
shot hoard DYOGENE_APPEARANCE=dark DYOGENE_SCREEN=hoard
shot suspects DYOGENE_APPEARANCE=dark DYOGENE_SCREEN=suspects
shot remove DYOGENE_APPEARANCE=dark DYOGENE_SELECT="Movies/Wedding film master.mp4" DYOGENE_FOCUS_PARENT=1 DYOGENE_SHEET=secure DYOGENE_SNAPSHOT_DELAY=4

# The welcome screen scans nothing, so it needs no demo data.
env DYOGENE_WINDOW_SIZE=1400x860 DYOGENE_APPEARANCE=dark DYOGENE_SNAPSHOT="$PWD/$out/welcome.png" "$app" >/dev/null 2>&1
sips -Z 1600 "$out/welcome.png" >/dev/null
print "readme-images: $out/welcome.png"
