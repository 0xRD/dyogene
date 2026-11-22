#!/bin/zsh
# Builds Dyogène and installs it to /Applications, replacing an older copy cleanly.
set -euo pipefail
cd "${0:A:h}/.."
scripts/build-app.sh
osascript -e 'tell application id "io.github.0xrd.dyogene" to quit' 2>/dev/null || true
rm -rf /Applications/Dyogene.app
ditto build/Dyogene.app /Applications/Dyogene.app
print "install: /Applications/Dyogene.app"
