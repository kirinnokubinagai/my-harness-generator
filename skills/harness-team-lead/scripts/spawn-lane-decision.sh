#!/usr/bin/env bash
# spawn-lane-decision.sh — decide whether the lead may spawn lane-N right now.
#
# A lane is the four-teammate group (analyst-N, engineer-N, e2e-reviewer-N,
# reviewer-N). The lead consults this script before adding a new lane to the
# team and acts mechanically on the printed DECISION:
#
#   DECISION=SPAWN  → call Agent({}) for each name in NAMES
#   DECISION=SKIP   → all four teammates are already in the team config; reuse
#   DECISION=REFUSE → surface REASON to the user and do NOT call Agent({})
#
# Checks performed in order:
#   1. <root>/.my-harness/.config exists           → else REFUSE init-required
#   2. team config has no suffixed names like
#      analyst-N-2 / engineer-N-3                 → else REFUSE corrupt
#   3. lane-N's four canonical names are
#      either all present (→ SKIP) or all absent  → else REFUSE partial
#   4. Reclaimable RAM, swap, compressor are
#      within thresholds                          → else REFUSE pressure
#
# Thresholds (override in <root>/.my-harness/.config):
#   HARNESS_LANE_RAM_MB        default 4096   (one lane ≈ 4 teammates ≈ 4 GB)
#   HARNESS_LANE_SWAP_MAX_MB   default 1024
#   HARNESS_LANE_COMP_MAX_MB   default 6144
#
# Output (stdout, key=value lines):
#   DECISION=<SPAWN|SKIP|REFUSE>
#   LANE=<N>
#   NAMES=analyst-N engineer-N e2e-reviewer-N reviewer-N
#   REASON=<short>
#
# Usage:
#   bash spawn-lane-decision.sh <N> [<root>]
#     N      — lane number (1..4)
#     root   — project root (defaults to $PWD); must contain .my-harness/.config
#
# Exit code is always 0; the lead reads DECISION, not the exit code.

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

# >>> TEST-LOG (REMOVE AFTER DEBUGGING) — investigates why /harness-team-lead crashes
__test_log() {
  local logdir="$ROOT/.my-harness/logs"
  mkdir -p "$logdir" 2>/dev/null
  printf '[%s] [pid=%d] [spawn-lane-decision] %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$*" \
    >> "$logdir/harness-test.log" 2>/dev/null
}
__test_log "STARTED lane=$N root=$ROOT argv=$*"
# <<< TEST-LOG

emit() {
  # >>> TEST-LOG (REMOVE AFTER DEBUGGING)
  __test_log "DECISION=$1 lane=$N reason=$2"
  # <<< TEST-LOG
  echo "DECISION=$1"
  echo "LANE=$N"
  echo "NAMES=$NAMES"
  echo "REASON=$2"
  exit 0
}

# 0) lane number must be 1..4
case "$N" in
  1|2|3|4) : ;;
  *) emit REFUSE "invalid-lane: '$N' (must be 1..4)" ;;
esac

# 1) project initialized
if [ ! -f "$ROOT/.my-harness/.config" ]; then
  emit REFUSE "init-required: $ROOT/.my-harness/.config not found — run /my-harness-init"
fi

# 2 + 3) inspect team config for corruption and existing membership
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

  # Suffix detection: names like analyst-N-M / engineer-N-M (Claude Code's
  # auto-disambiguation when an Agent({name:...}) call collides with a live
  # teammate). The team is no longer trustworthy and must be removed by the
  # user before any further spawns.
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

# 4) live resource check
CFG="$ROOT/.my-harness/.config"
RAM_THRESH_MB=$(awk -F= '$1=="HARNESS_LANE_RAM_MB"{gsub(/"/,"",$2); print $2; exit}' "$CFG" 2>/dev/null)
SWAP_THRESH_MB=$(awk -F= '$1=="HARNESS_LANE_SWAP_MAX_MB"{gsub(/"/,"",$2); print $2; exit}' "$CFG" 2>/dev/null)
COMP_THRESH_MB=$(awk -F= '$1=="HARNESS_LANE_COMP_MAX_MB"{gsub(/"/,"",$2); print $2; exit}' "$CFG" 2>/dev/null)
RAM_THRESH_MB=${RAM_THRESH_MB:-4096}
SWAP_THRESH_MB=${SWAP_THRESH_MB:-1024}
COMP_THRESH_MB=${COMP_THRESH_MB:-6144}

if [ -r /proc/meminfo ]; then
  AVAIL_KB=$(awk '/^MemAvailable:/{print $2; exit}' /proc/meminfo)
  AVAIL_MB=$(( ${AVAIL_KB:-0} / 1024 ))
  SWAP_USED_KB=$(awk '/^SwapTotal:/{t=$2}/^SwapFree:/{f=$2} END{print (t-f)>0?(t-f):0}' /proc/meminfo)
  SWAP_USED_MB=$(( ${SWAP_USED_KB:-0} / 1024 ))
  COMP_MB=0
elif command -v vm_stat >/dev/null 2>&1; then
  PAGE_BYTES=$(vm_stat | awk '/page size of/{print $8}')
  PAGE_BYTES=${PAGE_BYTES:-16384}
  PFREE=$(vm_stat | awk '/Pages free:/{gsub(/\./,"",$3); print $3; exit}')
  PINACT=$(vm_stat | awk '/Pages inactive:/{gsub(/\./,"",$3); print $3; exit}')
  PSPEC=$(vm_stat | awk '/Pages speculative:/{gsub(/\./,"",$3); print $3; exit}')
  AVAIL_MB=$(( ( ${PFREE:-0} + ${PINACT:-0} + ${PSPEC:-0} ) * PAGE_BYTES / 1024 / 1024 ))
  COMP_MB=$(( $(sysctl -n vm.compressor_bytes_used 2>/dev/null || echo 0) / 1024 / 1024 ))
  SWAP_RAW=$(sysctl -n vm.swapusage 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="used")print $(i+2)}' | sed 's/M$//')
  SWAP_USED_MB=${SWAP_RAW%.*}
  SWAP_USED_MB=${SWAP_USED_MB:-0}
else
  emit REFUSE "memory-probe-failed: neither /proc/meminfo nor vm_stat available"
fi

SNAP="reclaimable=${AVAIL_MB}MB swap=${SWAP_USED_MB}MB compressor=${COMP_MB}MB"

# >>> TEST-LOG (REMOVE AFTER DEBUGGING)
__test_log "RESOURCE_PROBE lane=$N reclaimable_mb=$AVAIL_MB swap_used_mb=$SWAP_USED_MB compressor_mb=$COMP_MB ram_threshold=$RAM_THRESH_MB swap_threshold=$SWAP_THRESH_MB comp_threshold=$COMP_THRESH_MB"
__test_log "PROCSNAP lane=$N node_count=$(pgrep -c node 2>/dev/null || echo 0) claude_count=$(pgrep -c claude 2>/dev/null || echo 0) total_procs=$(ps -A 2>/dev/null | wc -l | tr -d ' ')"
# <<< TEST-LOG

[ "$AVAIL_MB" -ge "$RAM_THRESH_MB" ] || emit REFUSE "low-ram: $SNAP (need ≥ ${RAM_THRESH_MB}MB) — wait for an existing lane to finish, then retry"
[ "$SWAP_USED_MB" -le "$SWAP_THRESH_MB" ] || emit REFUSE "swap-pressure: $SNAP (need swap ≤ ${SWAP_THRESH_MB}MB) — wait for an existing lane to finish"
[ "$COMP_MB" -le "$COMP_THRESH_MB" ] || emit REFUSE "compressor-pressure: $SNAP (need compressor ≤ ${COMP_THRESH_MB}MB) — wait for an existing lane to finish"

emit SPAWN "ok: $SNAP"
