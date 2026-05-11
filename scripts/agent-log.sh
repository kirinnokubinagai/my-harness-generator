#!/usr/bin/env bash
# agent-log.sh — append one structured event line to <root>/.my-harness/logs/agents.log.
#
# Called by analyst-N / engineer-N / e2e-reviewer-N / reviewer-N (and the lead)
# at action boundaries so the live state of every lane is observable from a
# single tail-able file. monitor-agents.sh consumes the same file.
#
# Usage:
#   bash agent-log.sh <root> <agent> <event...key=value pairs separated by spaces>
#
# Example:
#   bash agent-log.sh "$ROOT" engineer-1 step=3-codex status=start session=eng-1-2
#   bash agent-log.sh "$ROOT" engineer-1 step=3-codex status=done exit=0 changed=8
#   bash agent-log.sh "$ROOT" analyst-2 step=5-commit status=blocked-merge-conflict
#
# The line is one tab-separated record:
#   <ISO-8601 UTC>\t<agent>\t<key=value k=v ...>
#
# Idempotent. Best-effort: never fails the caller's shell. If the log directory
# can't be created the line is silently dropped.

if [ $# -lt 3 ]; then
  echo "::error:: agent-log.sh: usage: bash agent-log.sh <root> <agent> <event-key=value ...>" >&2
  exit 64
fi

__ROOT="$1"; shift
__AGENT="$1"; shift

# Resolve project root from any subdir (worktree / dev / lanes/feat-*).
__resolve_project_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    [ -f "$d/.my-harness/.config" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}
__ROOT="$(__resolve_project_root "$__ROOT")"

__LOG_DIR="$__ROOT/.my-harness/logs"
mkdir -p "$__LOG_DIR" 2>/dev/null || exit 0

__TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
__LINE="$(printf '%s\t%s\t%s\n' "$__TS" "$__AGENT" "$*")"

# Atomic append (single write syscall on POSIX).
printf '%s\n' "$__LINE" >> "$__LOG_DIR/agents.log" 2>/dev/null || exit 0

# Mirror to a per-agent file too so monitor-agents.sh can grep efficiently.
__SAFE_AGENT="$(printf '%s' "$__AGENT" | tr -c '[:alnum:]-' '_')"
printf '%s\n' "$__LINE" >> "$__LOG_DIR/agent-$__SAFE_AGENT.log" 2>/dev/null || true
