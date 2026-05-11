#!/usr/bin/env bash
# doctor.sh — pre-flight diagnostics for the my-harness runtime.
# Run before /harness-team-lead to catch the common 9-out-of-10 failure modes.
#
# Usage:
#   bash scripts/doctor.sh             # human-readable
#   bash scripts/doctor.sh --json      # machine-readable summary (requires jq)
#
# Exit codes:
#   0   all checks pass
#   1   one or more checks failed
#   2   advisory warnings only

set -u

JSON=0
[ "${1:-}" = "--json" ] && JSON=1

__resolve_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}
ROOT="$(__resolve_root "$PWD")"

# Each check appends one record. Three parallel arrays keep things simple while
# avoiding bash 4-only associative arrays (macOS ships bash 3.2 by default).
KINDS=()
NAMES=()
MSGS=()
PASS=0; FAIL=0; WARN=0

record() {
  local kind="$1" name="$2" msg="$3"
  KINDS+=("$kind")
  NAMES+=("$name")
  MSGS+=("$msg")
  case "$kind" in
    PASS) PASS=$((PASS+1)) ;;
    FAIL) FAIL=$((FAIL+1)) ;;
    WARN) WARN=$((WARN+1)) ;;
  esac
}

# --- harness layout ---
[ -d "$ROOT/.bare" ]                && record PASS "bare-repo"    ".bare/ found at $ROOT" \
                                    || record FAIL "bare-repo"    ".bare/ missing — run /my-harness-init or /my-harness-adopt"
[ -f "$ROOT/.my-harness/.config" ]  && record PASS "config"       "$ROOT/.my-harness/.config present" \
                                    || record FAIL "config"       ".my-harness/.config missing"

# --- recommend-lanes vs configured MAX_LANES ---
MAX_LANES=$(awk -F= '$1=="MAX_LANES"{gsub(/"/,"",$2); print $2; exit}' "$ROOT/.my-harness/.config" 2>/dev/null)
MAX_LANES=${MAX_LANES:-4}
LIB="$(dirname "$0")/lib/recommend-lanes.sh"
[ -f "$LIB" ] || LIB="$ROOT/.my-harness/scripts/lib/recommend-lanes.sh"
if [ -f "$LIB" ]; then
  # shellcheck disable=SC1090
  . "$LIB"
  REC_RAW=$(recommend_lanes)
  REC_NUM="${REC_RAW%%|*}"
  REC_DETAIL="${REC_RAW#*|}"
  if [ "$MAX_LANES" -le "$REC_NUM" ]; then
    record PASS "max-lanes" "MAX_LANES=$MAX_LANES (recommend ≤$REC_NUM; $REC_DETAIL)"
  else
    record WARN "max-lanes" "MAX_LANES=$MAX_LANES > recommended $REC_NUM ($REC_DETAIL). Consider 'bash scripts/prune-lanes.sh --max $REC_NUM'."
  fi
fi

# --- tools on PATH ---
for tool in git bash jq rsync; do
  if command -v "$tool" >/dev/null 2>&1; then
    record PASS "tool-$tool" "$(command -v "$tool")"
  else
    record FAIL "tool-$tool" "$tool not on PATH"
  fi
done

# --- Codex auth (only if any USE_CODEX_* is yes) ---
ANY_CODEX=$(awk -F= '$1 ~ /^USE_CODEX/ && $2=="yes"{print "y"; exit}' "$ROOT/.my-harness/.config" 2>/dev/null)
if [ "$ANY_CODEX" = "y" ]; then
  if command -v codex >/dev/null 2>&1; then
    if codex --version >/dev/null 2>&1; then
      record PASS "codex-cli" "$(codex --version 2>/dev/null | head -1)"
    else
      record FAIL "codex-cli" "codex binary present but --version failed"
    fi
    if [ -s "$HOME/.codex/auth.json" ]; then
      record PASS "codex-auth" "~/.codex/auth.json present"
    else
      record FAIL "codex-auth" "~/.codex/auth.json missing — run: codex login"
    fi
  else
    record FAIL "codex-cli" "codex not on PATH but USE_CODEX_*=yes — install or set USE_CODEX=no"
  fi
fi

# --- Codex daemon liveness ---
if [ -f "$ROOT/.my-harness/codex-app-server.pid" ]; then
  PID=$(cat "$ROOT/.my-harness/codex-app-server.pid" 2>/dev/null)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    record PASS "codex-daemon" "running (pid=$PID)"
  else
    record WARN "codex-daemon" "stale pid file (pid=$PID not running)"
  fi
fi

# --- spawn-lane-decision dry run for lane 1 ---
SPAWN="$(dirname "$0")/../skills/harness-team-lead/scripts/spawn-lane-decision.sh"
[ -f "$SPAWN" ] || SPAWN="$ROOT/.my-harness/skills/harness-team-lead/scripts/spawn-lane-decision.sh"
if [ -f "$SPAWN" ]; then
  D=$(bash "$SPAWN" 1 "$ROOT" 2>/dev/null | awk -F= '$1=="DECISION"{print $2; exit}')
  case "$D" in
    SPAWN|SKIP) record PASS "lane-gate" "lane-1 → $D" ;;
    REFUSE)     record WARN "lane-gate" "lane-1 → REFUSE (see spawn-lane-decision output)" ;;
    *)          record WARN "lane-gate" "spawn-lane-decision returned no DECISION" ;;
  esac
fi

# --- environment env-vars ---
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" = "1" ]; then
  record PASS "agent-teams-env" "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
else
  record WARN "agent-teams-env" "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS not set — /harness-team-lead will fail"
fi

# --- output ---
n=${#KINDS[@]}
if [ "$JSON" -eq 1 ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo '{"error":"jq required for --json output"}' >&2
    exit 64
  fi
  jq_args=()
  for ((i=0; i<n; i++)); do
    jq_args+=(--arg "k$i" "${KINDS[$i]}" --arg "n$i" "${NAMES[$i]}" --arg "m$i" "${MSGS[$i]}")
  done
  jq_filter='{pass:'"$PASS"',fail:'"$FAIL"',warn:'"$WARN"',checks:['
  for ((i=0; i<n; i++)); do
    [ $i -gt 0 ] && jq_filter+=','
    jq_filter+='{kind:$k'"$i"',name:$n'"$i"',msg:$m'"$i"'}'
  done
  jq_filter+=']}'
  jq -n "${jq_args[@]}" "$jq_filter"
else
  for ((i=0; i<n; i++)); do
    case "${KINDS[$i]}" in
      PASS) sym="✓" ;;
      FAIL) sym="✗" ;;
      WARN) sym="!" ;;
    esac
    printf '%s %-20s %s\n' "$sym" "${NAMES[$i]}" "${MSGS[$i]}"
  done
  echo
  echo "summary: $PASS pass, $FAIL fail, $WARN warn"
fi

[ "$FAIL" -gt 0 ] && exit 1
[ "$WARN" -gt 0 ] && exit 2
exit 0
