#!/usr/bin/env bash
# List pending issues for /harness-team-lead.
# Source is determined by USE_GITHUB_ISSUES in .my-harness/.config:
#   yes → `gh issue list --label ready --json ...`
#   no  → walk dev/docs/task/child/*.md for `status: pending`
#
# Usage: list-pending-issues.sh [<root>]
#   <root> defaults to $PWD. .my-harness/.config is read from <root>.
#
# Stdout (one per line): `<id>\t<title>` ordered FIFO

set -u

ROOT="${1:-$PWD}"
CFG="$ROOT/.my-harness/.config"

if [ ! -f "$CFG" ]; then
  echo "::error:: $CFG not found" >&2
  exit 1
fi

USE_GITHUB=$(grep -E "^USE_GITHUB_ISSUES=" "$CFG" | head -1 | cut -d= -f2 | tr -d '"')

if [ "$USE_GITHUB" = "yes" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "::error:: USE_GITHUB_ISSUES=yes but \`gh\` CLI not in PATH" >&2
    exit 2
  fi
  gh issue list --label ready --json number,title --limit 50 \
    --jq '.[] | "\(.number)\t\(.title)"' 2>/dev/null
else
  TASK_DIR="$ROOT/dev/docs/task/child"
  [ -d "$TASK_DIR" ] || TASK_DIR="$ROOT/docs/task/child"
  if [ ! -d "$TASK_DIR" ]; then
    echo "::error:: task directory not found at $TASK_DIR" >&2
    exit 3
  fi
  for f in "$TASK_DIR"/*.md; do
    [ -f "$f" ] || continue
    STATUS=$(awk '/^---$/{c++; next} c==1 && /^status:/{print $2; exit}' "$f")
    if [ "$STATUS" = "pending" ]; then
      ID=$(basename "$f" .md)
      TITLE=$(awk '/^---$/{c++; next} c==1 && /^title:/{sub(/^title: */,""); print; exit}' "$f")
      printf '%s\t%s\n' "$ID" "${TITLE:-$ID}"
    fi
  done
fi
