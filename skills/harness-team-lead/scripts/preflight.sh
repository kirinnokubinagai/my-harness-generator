#!/usr/bin/env bash
# preflight.sh — resource gate for /harness-team-lead.
#
# Refuses to start if the host cannot safely host even one lane (4 teammates).
# The per-lane go/no-go gate lives in spawn-lane-decision.sh and re-checks
# resources before each lane is added.
#
# Gates (in order):
#   0. <root>/.my-harness/.config exists                  → exit 4 init-required
#   1. Data volume has ≥ 20 GB free                       → exit 1 disk
#   2. Reclaimable RAM ≥ 4 GB
#      AND swap ≤ 1 GB
#      AND compressor ≤ 6 GB                              → exit 2 memory
#   3. No nix-collect-garbage / nix-store --gc running    → exit 3 nix-gc
#
# Stdout: nothing on failure; on success, an info line on stderr.
# This script does NOT mutate the caller's environment.

set -u

# Resolve project root from any cwd (project root, dev/, lanes/feat-*/). The
# project root is the directory holding .bare/. Falls back to the original arg
# if no .bare/ ancestor is found.
__resolve_project_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}

ROOT="$(__resolve_project_root "${1:-$PWD}")"

# >>> TEST-LOG (REMOVE AFTER DEBUGGING) — investigates why /harness-team-lead crashes
__test_log() {
  local logdir="$ROOT/.my-harness/logs"
  mkdir -p "$logdir" 2>/dev/null
  printf '[%s] [pid=%d] [preflight] %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$*" \
    >> "$logdir/harness-test.log" 2>/dev/null
}
__test_log "STARTED root=$ROOT argv=$*"
# <<< TEST-LOG

if [ ! -f "$ROOT/.my-harness/.config" ]; then
  # >>> TEST-LOG
  __test_log "EXIT code=4 reason=init-required"
  # <<< TEST-LOG
  cat >&2 <<EOF
::error:: $ROOT/.my-harness/.config not found.
         Run /my-harness-init first.
EOF
  exit 4
fi

DATA_AVAIL_GB=$(df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')
DATA_AVAIL_GB=${DATA_AVAIL_GB:-$(df -g / 2>/dev/null | awk 'NR==2{print $4}')}
# >>> TEST-LOG (REMOVE AFTER DEBUGGING)
__test_log "DISK_GATE avail_gb=${DATA_AVAIL_GB:-?} threshold_gb=20"
# <<< TEST-LOG
if [ "${DATA_AVAIL_GB:-0}" -lt 20 ]; then
  # >>> TEST-LOG
  __test_log "EXIT code=1 reason=disk avail_gb=${DATA_AVAIL_GB}"
  # <<< TEST-LOG
  cat >&2 <<EOF
::error:: insufficient disk: ${DATA_AVAIL_GB} GB available
         /harness-team-lead needs ≥ 20 GB for nix store, pnpm store, and
         per-lane worktrees. Free disk space, then retry.
EOF
  exit 1
fi

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
  # >>> TEST-LOG (REMOVE AFTER DEBUGGING)
  __test_log "EXIT code=2 reason=no-mem-probe"
  # <<< TEST-LOG
  echo "::error:: preflight.sh: cannot probe memory (no /proc/meminfo, no vm_stat)" >&2
  exit 2
fi

# >>> TEST-LOG (REMOVE AFTER DEBUGGING)
__test_log "MEM_GATE reclaimable_mb=$AVAIL_MB compressor_mb=$COMP_MB swap_used_mb=$SWAP_USED_MB ram_threshold=4096 swap_threshold=1024 comp_threshold=6144"
__test_log "PROCSNAP node_count=$(pgrep -c node 2>/dev/null || echo 0) claude_count=$(pgrep -c claude 2>/dev/null || echo 0) total_procs=$(ps -A 2>/dev/null | wc -l | tr -d ' ')"
# <<< TEST-LOG
if [ "$AVAIL_MB" -lt 4096 ] || [ "$COMP_MB" -gt 6144 ] || [ "$SWAP_USED_MB" -gt 1024 ]; then
  # >>> TEST-LOG
  __test_log "EXIT code=2 reason=memory-pressure reclaimable=$AVAIL_MB comp=$COMP_MB swap=$SWAP_USED_MB"
  # <<< TEST-LOG
  cat >&2 <<EOF
::error:: memory under pressure:
         reclaimable=${AVAIL_MB}MB compressor=${COMP_MB}MB swap=${SWAP_USED_MB}MB
         Need at least 4 GB reclaimable, compressor ≤ 6 GB, swap ≤ 1 GB to
         host even one lane. Close other heavy applications and retry.
EOF
  exit 2
fi

if pgrep -f "nix-collect-garbage|nix-store --gc|nix store gc" >/dev/null 2>&1; then
  # >>> TEST-LOG (REMOVE AFTER DEBUGGING)
  __test_log "EXIT code=3 reason=nix-gc-running"
  # <<< TEST-LOG
  cat >&2 <<EOF
::error:: nix garbage collection is currently running.
         Wait for it to finish (\`pgrep -af nix-collect-garbage\`), then retry.
EOF
  exit 3
fi

# >>> TEST-LOG (REMOVE AFTER DEBUGGING)
__test_log "EXIT code=0 reason=ok disk=${DATA_AVAIL_GB}GB ram=${AVAIL_MB}MB comp=${COMP_MB}MB swap=${SWAP_USED_MB}MB"
# <<< TEST-LOG
echo "[preflight] disk=${DATA_AVAIL_GB}GB reclaimable=${AVAIL_MB}MB compressor=${COMP_MB}MB swap=${SWAP_USED_MB}MB — OK" >&2
exit 0
