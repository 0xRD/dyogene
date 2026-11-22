#!/bin/zsh
# Installs the Dyogène skill for Claude Code into ~/.claude/skills/dyogene.
set -euo pipefail
cd "${0:A:h}/.."
target="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/dyogene"
mkdir -p "$target"
cp skill/dyogene/SKILL.md "$target/SKILL.md"
print "install-skill: installed $target/SKILL.md"
