#!/bin/zsh
# Renders Resources/icon-1024.png from scripts/render-icon.swift, then builds Resources/Dyogene.icns.
set -euo pipefail
cd "${0:A:h}/.."

swift scripts/render-icon.swift Resources/icon-1024.png

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
iconset="$work/Dyogene.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" Resources/icon-1024.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" Resources/icon-1024.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/Dyogene.icns
print "make-icns: wrote Resources/Dyogene.icns"
