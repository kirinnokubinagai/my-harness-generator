#!/usr/bin/env bash
# prune-lanes.sh — remove teammates whose lane number exceeds the current
# MAX_LANES from ~/.claude/teams/harness-team/config.json. Use after lowering
# MAX_LANES in .my-harness/.config (e.g. on memory pressure).
#
# Usage:
#   bash scripts/prune-lanes.sh                # use MAX_LANES from .config
#   bash scripts/prune-lanes.sh --max 2        # explicit override
#   bash scripts/prune-lanes.sh --dry-run      # report only
#
# Exit codes:
#   0  pruned (or no-op when nothing to prune)
#   2  team config missing
#   3  jq missing (required for safe edit)

set -u

DRY=0
MAX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --max) MAX="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --help|-h) sed -n '1,/^set -u/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

__resolve_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}
ROOT="$(__resolve_root "$PWD")"

if [ -z "$MAX" ]; then
  MAX=$(awk -F= '$1=="MAX_LANES"{gsub(/"/,"",$2); print $2; exit}' "$ROOT/.my-harness/.config" 2>/dev/null)
  MAX=${MAX:-4}
fi
case "$MAX" in 1|2|3|4) : ;; *) echo "MAX must be 1..4 (got $MAX)" >&2; exit 64 ;; esac

CFG="$HOME/.claude/teams/harness-team/config.json"
if [ ! -f "$CFG" ]; then
  echo "no team config at $CFG — nothing to prune"
  exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 3; }

DROP=$(jq -r --argjson max "$MAX" '
  .members[]?.name
  | select(test("^(analyst|engineer|e2e-reviewer|reviewer)-([0-9]+)$"))
  | . as $n
  | (capture("-(?<i>[0-9]+)$").i | tonumber) as $i
  | select($i > $max) | $n' "$CFG" | sort -u)

if [ -z "$DROP" ]; then
  echo "no teammates above MAX_LANES=$MAX — nothing to prune"
  exit 0
fi

echo "would prune (MAX_LANES=$MAX):"
echo "$DROP" | sed 's/^/  - /'

[ "$DRY" -eq 1 ] && exit 0

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
jq --argjson max "$MAX" '
  .members |= map(
    select(
      (.name | test("^(analyst|engineer|e2e-reviewer|reviewer)-([0-9]+)$") | not)
      or
      ((.name | capture("-(?<i>[0-9]+)$").i | tonumber) <= $max)
    )
  )' "$CFG" > "$TMP"
mv "$TMP" "$CFG"
trap - EXIT

echo "pruned. team config rewritten at $CFG"
