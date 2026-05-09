#!/usr/bin/env bash
# Idempotent check for the harness-team — used in Step 2 of /harness-team-lead.
# Prevents duplicate TeamCreate / Agent spawns on /loop wakeup re-entry.
#
# Stdout:
#   "skip"    — team is fully populated (16 teammates + lead). Skip TeamCreate AND all 16 Agent calls.
#   "create"  — no team file. Run TeamCreate + 16 Agent.
#   "broken"  — team file exists but member set is wrong. Manual cleanup required (do not auto-delete).
#
# Exit code is always 0; the caller branches on stdout.

set -u

TEAM_CFG="$HOME/.claude/teams/harness-team/config.json"

if [ ! -f "$TEAM_CFG" ]; then
  echo "create"
  exit 0
fi

# Extract member names. Prefer jq for correctness; fall back to a regex that
# excludes the top-level team name field (always "harness-team" here).
if command -v jq >/dev/null 2>&1; then
  EXISTING=$(jq -r '.members[].name' "$TEAM_CFG" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//')
else
  EXISTING=$(grep -o '"name": *"[^"]*"' "$TEAM_CFG" 2>/dev/null \
    | sed 's/.*"\([^"]*\)"$/\1/' \
    | grep -v '^harness-team$' \
    | sort -u | tr '\n' ' ' | sed 's/ $//')
fi

EXPECTED="analyst-1 analyst-2 analyst-3 analyst-4 e2e-reviewer-1 e2e-reviewer-2 e2e-reviewer-3 e2e-reviewer-4 engineer-1 engineer-2 engineer-3 engineer-4 reviewer-1 reviewer-2 reviewer-3 reviewer-4 team-lead"

if [ "$EXISTING" = "$EXPECTED" ]; then
  echo "skip"
elif [ -z "$EXISTING" ]; then
  echo "broken"
  echo "::warning:: $TEAM_CFG exists but contains no members. Manual fix needed." >&2
else
  echo "broken"
  echo "::warning:: $TEAM_CFG members mismatch:" >&2
  echo "  got:      $EXISTING" >&2
  echo "  expected: $EXPECTED" >&2
fi

exit 0
