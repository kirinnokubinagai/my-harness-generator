#!/usr/bin/env bash
# ensure-codex-daemon.sh — start (or recover) the shared `codex app-server`
# daemon iff USE_CODEX=yes in this project's .config. Best-effort: failure
# never blocks the init flow, since downstream codex-ask.sh always falls
# back to per-call stdio.
#
# Branch on the daemon script's `status` exit code so a stale pid file or
# dead socket doesn't leave the daemon in a half-broken state:
#   0 = daemon running and /readyz green        → no-op (reuse)
#   1 = daemon not running                      → start
#   2 = pid alive but socket / port file broken → restart (stop + start)
#
# Usage:
#   bash scripts/ensure-codex-daemon.sh <root>

set -u

ROOT="${1:?root required}"

if ! grep -q "^USE_CODEX=yes$" "$ROOT/.my-harness/.config" 2>/dev/null; then
  # USE_CODEX!=yes — no Codex calls expected, daemon serves no purpose.
  exit 0
fi

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
D="$HARNESS_DIR/skills/harness-codex-daemon/scripts/codex-daemon.sh"
[ -f "$D" ] || { echo "::warning:: $D not found — skipping daemon ensure" >&2; exit 0; }

bash "$D" status >/dev/null 2>&1
case $? in
  0) ;;                              # healthy — reuse
  1) bash "$D" start   || true ;;    # not running — bring one up
  *) bash "$D" restart || true ;;    # broken state — recover
esac
exit 0
