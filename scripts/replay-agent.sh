#!/usr/bin/env bash
# replay-agent.sh — agents.log から特定 lane / 期間の出来事を再生する。
# postmortem や教育素材として、過去のレーン動作を時系列で見直す。
#
# Usage:
#   bash scripts/replay-agent.sh --lane <N> [--since <ISO>] [--until <ISO>]
#   bash scripts/replay-agent.sh --name analyst-2 --since 2026-05-11T00:00:00Z
#
# Logs format (agent-log.sh):
#   <ISO-8601>\t<name>\t<step>\t<status>\t<message>

set -u

__resolve_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}
ROOT="$(__resolve_root "$PWD")"

LANE=""
NAME=""
SINCE=""
UNTIL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --lane)  LANE="$2";  shift 2 ;;
    --name)  NAME="$2";  shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

LOG="$ROOT/.my-harness/logs/agents.log"
[ -f "$LOG" ] || { echo "no log at $LOG" >&2; exit 1; }

if [ -n "$LANE" ] && [ -z "$NAME" ]; then
  NAME_RE="(analyst|engineer|e2e-reviewer|reviewer)-${LANE}\\b"
elif [ -n "$NAME" ]; then
  NAME_RE="^${NAME}\$"
else
  NAME_RE=".*"
fi

awk -F'\t' -v since="$SINCE" -v until="$UNTIL" -v re="$NAME_RE" '
  $2 ~ re &&
  (since == "" || $1 >= since) &&
  (until == "" || $1 <= until) {
    printf "[%s] %-22s %-20s %-12s %s\n", $1, $2, $3, $4, $5
  }
' "$LOG"
