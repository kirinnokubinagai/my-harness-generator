#!/usr/bin/env bash
# spawn-lane-decision.sh — decide whether the lead may spawn lane-N right now.
#
# A lane is the four-teammate group (analyst-N, engineer-N, e2e-reviewer-N,
# reviewer-N). The lead consults this script before adding a new lane and acts
# mechanically on the printed DECISION:
#
#   DECISION=SPAWN  → call Agent({}) for each name in NAMES
#   DECISION=SKIP   → all four teammates are already in the team config; reuse
#   DECISION=REFUSE → surface REASON to the user and do NOT call Agent({})
#
# Checks performed in order:
#   0. N is a positive integer
#   1. <root>/.my-harness/.config exists           → else REFUSE init-required
#   1a. N ≤ MAX_LANES                              → else REFUSE exceeds-max-lanes
#   2. team config has no suffixed names           → else REFUSE corrupt-team
#   3. lane-N's four canonical names are
#      either all present (→ SKIP) or all absent   → else REFUSE partial
#   4. reclaimable RAM / swap / compressor within
#      thresholds                                  → else REFUSE pressure
#
# Thresholds (override in <root>/.my-harness/.config):
#   HARNESS_LANE_RAM_MB        default 4096
#   HARNESS_LANE_SWAP_MAX_MB   default 1024
#   HARNESS_LANE_COMP_MAX_MB   default 6144

set -u

N="${1:-}"

__resolve_project_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}

ROOT="$(__resolve_project_root "${2:-$PWD}")"
NAMES="analyst-$N engineer-$N e2e-reviewer-$N reviewer-$N"

# Resolve plugin root from this script's location: skills/harness-team-lead/scripts/
PLUGIN_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PROBE="$PLUGIN_ROOT/scripts/lib/memory-probe.sh"
if [ ! -f "$PROBE" ]; then
  PROBE="$ROOT/.my-harness/scripts/lib/memory-probe.sh"
fi
# shellcheck disable=SC1090
[ -f "$PROBE" ] && . "$PROBE"

emit() {
  echo "DECISION=$1"
  echo "LANE=$N"
  echo "NAMES=$NAMES"
  echo "REASON=$2"
  exit 0
}

# 0) N must be a positive integer
case "$N" in
  ''|*[!0-9]*|0) emit REFUSE "invalid-lane: '$N' (must be a positive integer)" ;;
esac

# 1) project initialized
if [ ! -f "$ROOT/.my-harness/.config" ]; then
  emit REFUSE "init-required: $ROOT/.my-harness/.config not found — run /my-harness-init"
fi

# 1a) MAX_LANES gate. Hard cap at 4.
MAX_LANES=$(awk -F= '$1=="MAX_LANES"{gsub(/"/,"",$2); print $2; exit}' "$ROOT/.my-harness/.config" 2>/dev/null)
MAX_LANES=${MAX_LANES:-4}
case "$MAX_LANES" in
  1|2|3|4) : ;;
  *) MAX_LANES=4 ;;
esac
if [ "$N" -gt "$MAX_LANES" ]; then
  emit REFUSE "exceeds-max-lanes: lane-$N > MAX_LANES=$MAX_LANES (set in .my-harness/.config). Either run scripts/prune-lanes.sh to reclaim slots or raise MAX_LANES (cap 4)."
fi

# 2 + 3) inspect team config
TEAM_CFG="$HOME/.claude/teams/harness-team/config.json"
if [ -f "$TEAM_CFG" ]; then
  if command -v jq >/dev/null 2>&1; then
    MEMBERS=$(jq -r '.members[].name // empty' "$TEAM_CFG" 2>/dev/null | sort -u)
  else
    MEMBERS=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$TEAM_CFG" 2>/dev/null \
      | sed 's/.*"\([^"]*\)"$/\1/' \
      | grep -v '^harness-team$' \
      | sort -u)
  fi

  CORRUPT=$(printf '%s\n' "$MEMBERS" \
    | grep -E '^(analyst|engineer|e2e-reviewer|reviewer)-[0-9]+-[0-9]+$' \
    | tr '\n' ' ' | sed 's/ $//')
  if [ -n "$CORRUPT" ]; then
    emit REFUSE "corrupt-team: suffixed names detected ($CORRUPT) — delete ~/.claude/teams/harness-team/ and start a fresh session"
  fi

  PRESENT=0
  for n in $NAMES; do
    printf '%s\n' "$MEMBERS" | grep -qx "$n" && PRESENT=$(( PRESENT + 1 ))
  done

  if [ "$PRESENT" -eq 4 ]; then
    emit SKIP "already-spawned: all four lane-$N teammates are in the team config — reuse, do NOT call Agent({}) for any of these names"
  elif [ "$PRESENT" -gt 0 ]; then
    emit REFUSE "partial-lane: only $PRESENT of 4 lane-$N teammates present — delete ~/.claude/teams/harness-team/ and start a fresh session"
  fi
fi

# 4) live resource check via memory-probe.sh
CFG="$ROOT/.my-harness/.config"
RAM_THRESH_MB=$(awk -F= '$1=="HARNESS_LANE_RAM_MB"{gsub(/"/,"",$2); print $2; exit}' "$CFG" 2>/dev/null)
SWAP_THRESH_MB=$(awk -F= '$1=="HARNESS_LANE_SWAP_MAX_MB"{gsub(/"/,"",$2); print $2; exit}' "$CFG" 2>/dev/null)
COMP_THRESH_MB=$(awk -F= '$1=="HARNESS_LANE_COMP_MAX_MB"{gsub(/"/,"",$2); print $2; exit}' "$CFG" 2>/dev/null)
RAM_THRESH_MB=${RAM_THRESH_MB:-4096}
SWAP_THRESH_MB=${SWAP_THRESH_MB:-1024}
COMP_THRESH_MB=${COMP_THRESH_MB:-6144}

if ! type detect_avail_ram_mb >/dev/null 2>&1; then
  emit REFUSE "memory-probe-failed: scripts/lib/memory-probe.sh not loadable"
fi
AVAIL_MB=$(detect_avail_ram_mb)
SWAP_USED_MB=$(detect_swap_used_mb)
COMP_MB=$(detect_compressor_mb)
SNAP="reclaimable=${AVAIL_MB}MB swap=${SWAP_USED_MB}MB compressor=${COMP_MB}MB"

[ "$AVAIL_MB" -ge "$RAM_THRESH_MB" ] || emit REFUSE "low-ram: $SNAP (need ≥ ${RAM_THRESH_MB}MB) — wait for an existing lane to finish, then retry"
[ "$SWAP_USED_MB" -le "$SWAP_THRESH_MB" ] || emit REFUSE "swap-pressure: $SNAP (need swap ≤ ${SWAP_THRESH_MB}MB) — wait for an existing lane to finish"
[ "$COMP_MB" -le "$COMP_THRESH_MB" ] || emit REFUSE "compressor-pressure: $SNAP (need compressor ≤ ${COMP_THRESH_MB}MB) — wait for an existing lane to finish"

emit SPAWN "ok: $SNAP"
