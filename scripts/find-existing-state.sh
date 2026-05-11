#!/usr/bin/env bash
# find-existing-state.sh — walk up from PWD looking for .my-harness/init-state.json.
# Used by /my-harness-init pre-Phase 0 to decide between "resume" and "fresh start".
#
# Usage:
#   bash scripts/find-existing-state.sh
#
# Stdout: full path to init-state.json when found.
# Exit:   0 if found within 5 parent levels, 1 otherwise.

set -u

d="$PWD"
for _ in 1 2 3 4 5; do
  if [ -f "$d/.my-harness/init-state.json" ]; then
    printf '%s\n' "$d/.my-harness/init-state.json"
    exit 0
  fi
  d=$(dirname "$d")
done
exit 1
