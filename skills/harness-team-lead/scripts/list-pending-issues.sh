#!/usr/bin/env bash
# list-pending-issues.sh — list pending tasks for /harness-team-lead dispatch.
#
# Source is determined by USE_GITHUB_ISSUES in .my-harness/.config.
#
# Stdout (one per line, tab-separated, 4 fields):
#   <id>\t<lane>\t<owned_files_csv>\t<title>
#
#   id            — child task id (e.g. 0001-07) or GitHub issue number
#   lane          — preferred lane (1..4); empty if unspecified
#   owned_files   — comma-separated list of files this task is allowed to edit;
#                   empty if not declared
#   title         — short title
#
# USE_GITHUB_ISSUES=no: walk dev/docs/task/child/*.md, take entries with
# `status: pending` in front matter; lane / title from front matter; owned_files from
# the body line `**ファイル所有**: a, b, c` (or English `**Owned files**:`).
#
# USE_GITHUB_ISSUES=yes: `gh issue list --label ready` + jq parse:
#   - lane from a label of the form `lane-N`
#   - owned_files from a body line `**Owned files**: a, b, c` or `**ファイル所有**: ...`
#
# Usage:
#   bash list-pending-issues.sh [<root>]    # defaults to $PWD

set -u

__resolve_project_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}

ROOT="$(__resolve_project_root "${1:-$PWD}")"
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
  # Sort: issues with any "highest priority" label go first. The ZAP /
  # MobSF security-scan workflows file findings with `priority/p1`, so
  # those get dispatched ahead of regular feature work. We prepend a
  # numeric priority column (0 = highest, 9 = normal) for sort, then strip it.
  gh issue list --label ready --state open --json number,title,labels,body --limit 200 \
    --jq '.[] |
      . as $i |
      ($i.labels // [] | map(.name) | map(select(startswith("lane-"))) | .[0] // "" | sub("^lane-"; "")) as $lane |
      (
        ($i.body // "")
        | split("\n")
        | map(select(test("^\\s*\\*\\*(ファイル所有|Owned files)\\*\\*:")))
        | (.[0] // "")
        | sub(".*\\*\\*(ファイル所有|Owned files)\\*\\*:\\s*"; "")
      ) as $owned |
      (if ($i.labels // [] | map(.name) | any(. == "priority/p1" or . == "priority:highest")) then "0" else "9" end) as $prio |
      [$prio, ($i.number | tostring), $lane, $owned, ($i.title // "")] | @tsv' 2>/dev/null \
    | LC_ALL=C sort -t$'\t' -k1,1n -k2,2n \
    | cut -f2-
  exit 0
fi

# USE_GITHUB_ISSUES=no
TASK_DIR="$ROOT/dev/docs/task/child"
[ -d "$TASK_DIR" ] || TASK_DIR="$ROOT/docs/task/child"
if [ ! -d "$TASK_DIR" ]; then
  echo "::error:: task directory not found at $TASK_DIR" >&2
  exit 3
fi

for f in "$TASK_DIR"/*.md; do
  [ -f "$f" ] || continue
  STATUS=$(awk '/^---$/{c++; next} c==1 && /^status:/{sub(/^status:[[:space:]]*/,""); print; exit}' "$f")
  [ "$STATUS" = "pending" ] || continue

  ID=$(awk '/^---$/{c++; next} c==1 && /^id:/{sub(/^id:[[:space:]]*/,""); print; exit}' "$f")
  [ -n "$ID" ] || ID=$(basename "$f" .md)

  LANE=$(awk '/^---$/{c++; next} c==1 && /^lane:/{sub(/^lane:[[:space:]]*/,""); print; exit}' "$f")
  TITLE=$(awk '/^---$/{c++; next} c==1 && /^title:/{sub(/^title:[[:space:]]*/,""); print; exit}' "$f")

  # owned_files: body line starting with `**ファイル所有**:` or `**Owned files**:`
  OWNED=$(grep -m1 -E "^\*\*(ファイル所有|Owned files)\*\*:" "$f" 2>/dev/null \
    | sed -E 's/^\*\*(ファイル所有|Owned files)\*\*:[[:space:]]*//')

  printf '%s\t%s\t%s\t%s\n' "$ID" "$LANE" "$OWNED" "${TITLE:-$ID}"
done
