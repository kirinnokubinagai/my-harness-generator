#!/usr/bin/env bash
# monitor-agents.sh — live view + watchdog over <root>/.my-harness/logs/agents.log.
#
# Two modes:
#
#   1. Interactive view (default). Prints a status table to the terminal,
#      refreshing every <interval> seconds. Run in a separate terminal next to
#      your /harness-team-lead session.
#
#        bash monitor-agents.sh <root>
#        bash monitor-agents.sh <root> --interval 5
#
#   2. Watchdog. Scans agents.log every <interval> seconds, classifies
#      anomalies (stagnation, repeated blocks, codex-exec failures, codex
#      no-op), and appends them as JSONL to
#      <root>/.my-harness/logs/anomalies.jsonl. The lead reads that file at
#      the top of each Step 3 dispatch loop iteration and decides how to
#      intervene.
#
#        bash monitor-agents.sh <root> --watchdog
#        bash monitor-agents.sh <root> --watchdog --interval 60
#
# Both modes are safe to ^C; nothing else is killed.

set -u

ROOT=""
MODE="view"
INTERVAL=2
ANOMALY_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --watchdog)  MODE="watchdog";        shift ;;
    --interval)  INTERVAL="$2";          shift 2 ;;
    --out)       ANOMALY_FILE="$2";      shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# *//'
      exit 0
      ;;
    *)           ROOT="$1";              shift ;;
  esac
done

if [ -z "$ROOT" ]; then
  echo "::error:: monitor-agents.sh: missing <root>" >&2
  echo "         usage: monitor-agents.sh <root> [--watchdog] [--interval <s>] [--out <file>]" >&2
  exit 64
fi

# Resolve project root (the dir holding .bare/ or .my-harness/.config).
__resolve_project_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    [ -f "$d/.my-harness/.config" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}
ROOT="$(__resolve_project_root "$ROOT")"
LOG="$ROOT/.my-harness/logs/agents.log"
[ -z "$ANOMALY_FILE" ] && ANOMALY_FILE="$ROOT/.my-harness/logs/anomalies.jsonl"

mkdir -p "$ROOT/.my-harness/logs"

# ============================================================================
# Helpers
# ============================================================================

now_epoch() { date +%s; }

# Convert ISO-8601 UTC (Z suffix) to epoch seconds.
# CRITICAL: the timestamp is UTC. BSD date `-j -f` parses in the local TZ by
# default and silently produces wrong results — use `-ujf` to force UTC parse.
# GNU date needs `-u` similarly.
iso_to_epoch() {
  local iso="$1"
  date -ujf "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null \
    || date -u -d "$iso" +%s 2>/dev/null \
    || date -d "$iso" +%s 2>/dev/null
}

# ISO-8601 strings sort lexicographically when fully zero-padded with Z suffix,
# so we can pre-filter the log by string comparison and avoid invoking date(1)
# once per line.
cutoff_iso() {
  local sec="$1"
  date -u -j -v -"${sec}"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-${sec} seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# Pull the most recent line for a given agent.
last_line_for() {
  local agent="$1"
  local safe
  safe="$(printf '%s' "$agent" | tr -c '[:alnum:]-' '_')"
  local f="$ROOT/.my-harness/logs/agent-$safe.log"
  [ -f "$f" ] && tail -1 "$f"
}

# ============================================================================
# View mode
# ============================================================================

render_view() {
  clear
  printf '╔══════════════════════════════════════════════════════════════════════╗\n'
  printf '║ harness-team monitor — %s (refresh %ss)                  ║\n' "$(date '+%H:%M:%S')" "$INTERVAL"
  printf '╠══════════════════════════════════════════════════════════════════════╣\n'

  local lane role line ts agent rest
  for lane in 1 2 3 4; do
    for role in analyst engineer e2e-reviewer reviewer; do
      line="$(last_line_for "$role-$lane")"
      if [ -z "$line" ]; then
        printf '║ lane-%s  %-12s absent                                         ║\n' "$lane" "$role"
        continue
      fi
      ts="$(printf '%s' "$line" | awk -F'\t' '{print $1}')"
      rest="$(printf '%s' "$line" | awk -F'\t' '{print $3}' | cut -c1-40)"
      local age elapsed_h
      age=$(( $(now_epoch) - $(iso_to_epoch "$ts") ))
      if [ "$age" -lt 60 ]; then elapsed_h="${age}s"
      elif [ "$age" -lt 3600 ]; then elapsed_h="$(( age / 60 ))m"
      else elapsed_h="$(( age / 3600 ))h$(( (age % 3600) / 60 ))m"
      fi
      printf '║ lane-%s  %-12s %-40s  %6s  ║\n' "$lane" "$role" "$rest" "$elapsed_h"
    done
    printf '╠──────────────────────────────────────────────────────────────────────╣\n'
  done

  printf '║ recent events (tail %s):                                              ║\n' "10"
  if [ -f "$LOG" ]; then
    tail -10 "$LOG" | while IFS=$'\t' read -r ts agent rest; do
      printf '║   %s %-14s %-40s ║\n' "$(printf '%s' "$ts" | cut -c12-19)" "$agent" "$(printf '%s' "$rest" | cut -c1-40)"
    done
  else
    printf '║   (no log yet — waiting for agents.log to appear)                     ║\n'
  fi

  printf '╚══════════════════════════════════════════════════════════════════════╝\n'
  printf '\nanomalies: %s\n' "$ANOMALY_FILE"
  if [ -f "$ANOMALY_FILE" ]; then
    local n; n=$(wc -l < "$ANOMALY_FILE" | tr -d ' ')
    printf 'open anomalies: %s. Tail with: tail -f %s\n' "$n" "$ANOMALY_FILE"
  fi
  printf '\nCtrl-C to exit.\n'
}

# ============================================================================
# Watchdog mode
# ============================================================================

# Anomaly classification rules:
#   stagnation         — most recent event for an active lane is older than STAG_THRESHOLD seconds.
#   repeated-blocked   — same `status=blocked-*` reported by the same agent ≥3 times in the last window.
#   codex-exec-failure — agent reported `step=*-codex status=done exit=<non-zero>` ≥3 times in a row.
#   codex-no-op        — engineer reported `status=impl-done` but immediately after `changed=0`.
#   suffixed-name      — any agent name matching <role>-<N>-<M> appears (Claude Code auto-disambiguation).
#
# Thresholds (override via env):
#   HARNESS_STAGNATION_SEC      default 600 (10 min)
#   HARNESS_REPEATED_THRESHOLD  default 3
#   HARNESS_WINDOW_SEC          default 1800 (30 min look-back)

STAG_THRESHOLD="${HARNESS_STAGNATION_SEC:-600}"
REPEAT_THRESHOLD="${HARNESS_REPEATED_THRESHOLD:-3}"
WINDOW_SEC="${HARNESS_WINDOW_SEC:-1800}"

emit_anomaly() {
  local kind="$1" agent="$2" detail="$3"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","kind":"%s","agent":"%s","detail":"%s"}\n' \
    "$ts" "$kind" "$agent" "$(printf '%s' "$detail" | sed 's/"/\\"/g')" \
    >> "$ANOMALY_FILE"
}

scan_once() {
  [ -f "$LOG" ] || return 0
  local now; now=$(now_epoch)
  local cutoff_str; cutoff_str=$(cutoff_iso "$WINDOW_SEC")

  # Stagnation: walk per-agent files, take last line, compare ts.
  local f agent ts age
  for f in "$ROOT/.my-harness/logs"/agent-*.log; do
    [ -f "$f" ] || continue
    agent="$(basename "$f" .log | sed 's/^agent-//; s/_/-/g')"
    ts="$(tail -1 "$f" | awk -F'\t' '{print $1}')"
    [ -n "$ts" ] || continue
    age=$(( now - $(iso_to_epoch "$ts") ))
    # Skip absent / cleared / pr-created / shutdown idle states.
    local laststate; laststate="$(tail -1 "$f" | awk -F'\t' '{print $3}')"
    case "$laststate" in
      *status=cleared*|*status=ready*|*status=pr-created*|*status=shutdown*) continue ;;
    esac
    if [ "$age" -gt "$STAG_THRESHOLD" ]; then
      emit_anomaly stagnation "$agent" "no-event-for-${age}s last=$laststate"
    fi
  done

  # Repeated blocked / codex-exec-failure / codex-no-op (single AWK pass).
  # Pre-filter by ISO-8601 string comparison (fully zero-padded UTC sorts lexically).
  awk -F'\t' -v thresh="$REPEAT_THRESHOLD" -v cutoff_iso="$cutoff_str" '
    $1 < cutoff_iso { next }
    {
      ts = $1; agent = $2; rest = $3
      if (rest ~ /status=blocked-/) {
        match(rest, /status=blocked-[a-z-]+/)
        key = agent "|" substr(rest, RSTART, RLENGTH)
        blocked[key]++
        blocked_last[key] = rest
      }
      if (rest ~ /step=(codex-exec|.*-codex)/ && rest ~ /status=done/ && rest ~ /exit=[1-9]/) {
        codex_fail[agent]++
        codex_fail_last[agent] = rest
      }
      if (agent ~ /^engineer-/ && rest ~ /status=impl-done/ && rest ~ /changed=0/) {
        noop[agent]++
        noop_last[agent] = rest
      }
      if (agent ~ /^(analyst|engineer|e2e-reviewer|reviewer)-[0-9]+-[0-9]+$/) {
        suffix[agent] = 1
      }
    }
    END {
      for (k in blocked) if (blocked[k] >= thresh) {
        split(k, p, "|")
        printf "BLOCKED|%s|%s|count=%d last=%s\n", p[1], p[2], blocked[k], blocked_last[k]
      }
      for (a in codex_fail) if (codex_fail[a] >= thresh) {
        printf "CODEXFAIL|%s||count=%d last=%s\n", a, codex_fail[a], codex_fail_last[a]
      }
      for (a in noop) if (noop[a] >= 1) {
        printf "NOOP|%s||count=%d last=%s\n", a, noop[a], noop_last[a]
      }
      for (a in suffix) {
        printf "SUFFIX|%s||name=%s\n", a, a
      }
    }
  ' "$LOG" | while IFS='|' read -r kind agent extra detail; do
    case "$kind" in
      BLOCKED)    emit_anomaly repeated-blocked "$agent" "$extra $detail" ;;
      CODEXFAIL)  emit_anomaly codex-exec-failure "$agent" "$detail" ;;
      NOOP)       emit_anomaly codex-no-op "$agent" "$detail" ;;
      SUFFIX)     emit_anomaly suffixed-name "$agent" "$detail" ;;
    esac
  done
}

# ============================================================================
# Main
# ============================================================================

if [ "$MODE" = "watchdog" ]; then
  echo "[monitor] watchdog mode — scanning $LOG every ${INTERVAL}s, anomalies to $ANOMALY_FILE" >&2
  trap 'echo "[monitor] stopping" >&2; exit 0' INT TERM
  while :; do
    scan_once
    sleep "$INTERVAL"
  done
else
  trap 'echo; echo "[monitor] stopping" >&2; exit 0' INT TERM
  while :; do
    render_view
    sleep "$INTERVAL"
  done
fi
