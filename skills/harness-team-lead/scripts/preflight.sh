#!/usr/bin/env bash
# Resource pre-flight gate for /harness-team-lead.
# Refuses to proceed if disk / memory / nix-gc state would risk a kernel panic
# under 16 in-process teammates.
#
# Exit codes:
#   0  pre-flight passed, proceed
#   1  insufficient disk
#   2  memory under pressure
#   3  nix-collect-garbage already running
#   4  .my-harness/.config missing (project not initialized)

set -u

ROOT="${1:-$PWD}"

# 0) project initialized
if [ ! -f "$ROOT/.my-harness/.config" ]; then
  cat >&2 <<EOF
::error:: $ROOT/.my-harness/.config not found.
         Run /my-harness-init first.
EOF
  exit 4
fi

# 1) Disk: Data volume must have ≥ 30 GB available
DATA_AVAIL_GB=$(df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')
DATA_AVAIL_GB=${DATA_AVAIL_GB:-$(df -g / | awk 'NR==2{print $4}')}
if [ "${DATA_AVAIL_GB:-0}" -lt 20 ]; then
  cat >&2 <<EOF
::error:: insufficient disk: ${DATA_AVAIL_GB} GB available on /System/Volumes/Data
         /harness-team-lead requires ≥ 20 GB. Engineers running pnpm install /
         vitest / nix builds will hit ENOSPC and trigger lane stalls or kernel panic.
         Run cleanup before retrying:
           bash \$HOME/harness-monitor/cleanup.sh
         Or manually free space (~/.codex/sessions, ~/.codex/log,
         old git worktrees holding nix gc roots).
EOF
  exit 1
fi

# 2) Memory: macOS keeps "free" small intentionally — inactive pages are
#    reclaimable instantly. Real pressure shows up as compressor > 6 GB or
#    swap actually being used. Refuse only on those terminal signals.
PAGE_KB=16
PAGES_FREE=$(vm_stat 2>/dev/null | awk '/Pages free:/{gsub(/\./,"",$3); print $3}')
PAGES_INACTIVE=$(vm_stat 2>/dev/null | awk '/Pages inactive:/{gsub(/\./,"",$3); print $3}')
PAGES_SPEC=$(vm_stat 2>/dev/null | awk '/Pages speculative:/{gsub(/\./,"",$3); print $3}')
FREE_MB=$(( ${PAGES_FREE:-0} * PAGE_KB / 1024 ))
RECLAIMABLE_MB=$(( ( ${PAGES_FREE:-0} + ${PAGES_INACTIVE:-0} + ${PAGES_SPEC:-0} ) * PAGE_KB / 1024 ))
COMP_BYTES=$(sysctl -n vm.compressor_bytes_used 2>/dev/null)
COMP_MB=$(( ${COMP_BYTES:-0} / 1048576 ))
SWAP_USED_MB=$(sysctl -n vm.swapusage 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="used")print $(i+2)}' | sed 's/M$//')
SWAP_USED_INT=${SWAP_USED_MB%.*}

# Hard fail on real pressure signals only
if [ "${RECLAIMABLE_MB:-0}" -lt 1024 ] || [ "${COMP_MB:-0}" -gt 6144 ] || [ "${SWAP_USED_INT:-0}" -gt 1024 ]; then
  cat >&2 <<EOF
::error:: memory under real pressure:
         free=${FREE_MB}MB inactive+spec+free=${RECLAIMABLE_MB}MB
         compressor=${COMP_MB}MB swap_used=${SWAP_USED_MB:-0}MB
         /harness-team-lead spawns 16 in-process teammates (~5–8 GB committed).
         Close other heavy apps (Chrome, LM Studio, Codex.app) and re-run.
EOF
  exit 2
fi

# 3) No nix-collect-garbage / nix-store --gc currently running
if pgrep -f "nix-collect-garbage|nix-store --gc|nix store gc" >/dev/null 2>&1; then
  cat >&2 <<EOF
::error:: nix garbage collection is currently running.
         Wait for it to finish (\`pgrep -af nix-collect-garbage\`), then retry.
EOF
  exit 3
fi

# Pre-flight info (success path, on stderr to keep stdout clean)
echo "[preflight] disk_data=${DATA_AVAIL_GB}GB free=${FREE_MB}MB compressor=${COMP_MB}MB swap=${SWAP_USED_MB:-0}MB — OK" >&2

# Idempotency hint: if a team already exists, callers should skip TeamCreate
TEAM_CFG="$HOME/.claude/teams/harness-team/config.json"
if [ -f "$TEAM_CFG" ]; then
  EXISTING_LEAD=$(grep -o '"leadSessionId": *"[^"]*"' "$TEAM_CFG" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  echo "[preflight] existing harness-team detected (lead=${EXISTING_LEAD:-unknown}). Step 2 must reuse, not recreate." >&2
fi

exit 0
