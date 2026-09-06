#!/bin/bash
set -euo pipefail

# Restore .claude/skills symlinks for the emilkowalski/skills pack.
# .claude/ is gitignored, so these are recreated each session from
# the committed skill content in .agents/skills.
mkdir -p .claude/skills
for dir in .agents/skills/*/; do
  name="$(basename "$dir")"
  target="../../.agents/skills/$name"
  link=".claude/skills/$name"
  if [ ! -e "$link" ]; then
    ln -s "$target" "$link"
  fi
done
