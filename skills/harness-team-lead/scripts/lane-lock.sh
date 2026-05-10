#!/usr/bin/env bash
# Project-level lock to serialize heavy commands across the 4 harness lanes.
#
# Why: `nix develop --command pnpm install` (and similar heavy nix-shell + worker-pool
# commands) each fork 200+ helper node processes. Running 4 of them concurrently from
# 4 lanes saturates the macOS compressor + swap → kernel watchdog panic. Running them
# under this lock makes the first lane warm the nix store + pnpm store, then subsequent
# lanes resolve from cache (~10x faster + ~10x fewer helpers).
#
# Why mkdir-based, not flock: macOS does not ship `flock(1)`. `mkdir` is atomic on
# every POSIX filesystem (succeeds or fails atomically). It also lets us drop a holder
# file inside the lockdir for diagnostics.
#
# Usage:
#   bash lane-lock.sh <lock-name> <command...>
#
# Example:
#   bash skills/harness-team-lead/scripts/lane-lock.sh pnpm-install \
#     nix develop --command pnpm install
#   bash skills/harness-team-lead/scripts/lane-lock.sh vitest \
#     nix develop --command pnpm exec vitest run
#
# Lock dir lives at <project-root>/.my-harness/.<lock-name>.lockdir — project-scoped,
# survives across lanes (worktrees), discarded with the project.
#
# Behavior:
#   - Tries non-blocking acquisition first via `mkdir`. If acquired, runs immediately.
#   - If contended, polls every 2 s with a single-line status to stderr.
#   - Stale lock detection: if holder pid is no longer alive, lock is reclaimed.
#   - Cleanup on normal exit + signals.
#   - Exit code is the wrapped command's exit code.

set -u

if [ $# -lt 2 ]; then
  cat >&2 <<EOF
::error:: lane-lock.sh requires <lock-name> + <command...>
  usage: bash lane-lock.sh <lock-name> <command...>
  example: bash lane-lock.sh pnpm-install nix develop --command pnpm install
EOF
  exit 64
fi

LOCK_NAME="$1"
shift

# Walk up from $PWD until .my-harness/.config (project root). Each lane worktree is
# inside the same project root, so all 4 lanes share the same lock dir.
ROOT="$PWD"
while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/.my-harness/.config" ]; do
  ROOT="$(dirname "$ROOT")"
done
if [ ! -f "$ROOT/.my-harness/.config" ]; then
  echo "::error:: lane-lock.sh: no .my-harness/.config found walking up from $PWD" >&2
  exit 65
fi

LOCK_DIR="$ROOT/.my-harness/.${LOCK_NAME}.lockdir"
HOLDER="$LOCK_DIR/holder"
mkdir -p "$ROOT/.my-harness"

cleanup() {
  # Only remove if WE own it (holder file's PID matches us).
  if [ -f "$HOLDER" ] && [ "$(awk -F'pid=' '{print $2}' "$HOLDER" 2>/dev/null | awk '{print $1}')" = "$$" ]; then
    rm -f "$HOLDER"
    rmdir "$LOCK_DIR" 2>/dev/null
  fi
}
trap 'cleanup; exit 130' INT TERM
trap cleanup EXIT

acquire() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "lane=$(basename "$PWD") pid=$$ ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) cmd=$*" > "$HOLDER"
    return 0
  fi
  return 1
}

is_stale() {
  # Stale if no holder file, or holder pid no longer alive.
  [ ! -f "$HOLDER" ] && return 0
  local pid
  pid=$(awk -F'pid=' '{print $2}' "$HOLDER" 2>/dev/null | awk '{print $1}')
  [ -z "$pid" ] && return 0
  kill -0 "$pid" 2>/dev/null || return 0
  return 1
}

WAITED=0
while ! acquire "$@"; do
  if is_stale; then
    echo "[lane-lock:$LOCK_NAME] reclaiming stale lock (previous holder dead)" >&2
    rm -f "$HOLDER" 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null
    continue
  fi
  if [ "$WAITED" -eq 0 ]; then
    echo "[lane-lock:$LOCK_NAME] waiting for another lane (holder=$(cat "$HOLDER" 2>/dev/null | head -1)) — heavy ops serialized to prevent fork-bomb" >&2
    WAITED=1
  fi
  sleep 2
done

# Run the wrapped command, propagate its exit code.
"$@"
RC=$?
exit $RC
