#!/usr/bin/env bash
# Summary: Checks whether multiple child issues under a parent issue are simultaneously
#          generating Drizzle migrations. If two or more branches under the same parent
#          touch files in drizzle/, emits a warning and exits with an error.
# Usage: bash .harness/scripts/check-migration-conflict.sh <parent-issue-number>
set -euo pipefail
PARENT="${1:?parent issue number required}"
cd "$(git rev-parse --show-toplevel)"

# Retrieve branches derived from child issues linked to the parent via GitHub
CHILDREN=$(gh issue view "$PARENT" --json body --jq '.body' | grep -oE '#[0-9]+' | tr -d '#' || true)

OFFENDERS=()
for c in $CHILDREN; do
  BR=$(gh pr list --search "$c" --state open --json headRefName --jq '.[0].headRefName' 2>/dev/null || true)
  [ -z "$BR" ] && continue
  TOUCHED=$(git diff --name-only origin/dev..."origin/$BR" -- drizzle/ 2>/dev/null | wc -l | tr -d ' ')
  if [ "$TOUCHED" != "0" ]; then
    OFFENDERS+=("$BR(#$c) drizzle/ file count=$TOUCHED")
  fi
done

if [ "${#OFFENDERS[@]}" -gt 1 ]; then
  echo "::error:: Multiple child issues under parent #$PARENT are generating migrations:"
  for o in "${OFFENDERS[@]}"; do echo "  - $o"; done
  echo "Fix: Consolidate all migrations into a single child issue (prevents ordering conflicts)."
  exit 1
fi

echo "[check-migration-conflict] OK"
