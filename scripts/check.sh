#!/bin/zsh
# Quality gate: release build with zero warnings, then the tests.
set -euo pipefail
cd "${0:A:h}/.."
output=$(swift build -c release 2>&1) || { print -r -- "$output"; exit 1; }
if print -r -- "$output" | grep -q "warning:"; then
    print -r -- "$output" | grep "warning:"
    print -u2 "check: warnings found"
    exit 1
fi
scripts/test.sh
