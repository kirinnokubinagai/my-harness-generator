#!/usr/bin/env bash
# doctor.sh — pre-flight diagnostics for the my-harness runtime.
# Run before /harness-team-lead to catch the common 9-out-of-10 failure modes.
#
# Usage:
#   bash scripts/doctor.sh             # human-readable
#   bash scripts/doctor.sh --json      # machine-readable summary
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

PASS=0; FAIL=0; WARN=0
RESULTS=""

record() {
  local kind="$1" name="$2" msg="$3"
  case "$kind" in
    PASS) PASS=$((PASS+1)) ;;
    FAIL) FAIL=$((FAIL+1)) ;;
    WARN) WARN=$((WARN+1)) ;;
  esac
  RESULTS="${RESULTS}${kind}|${name}|${msg}
"
}

# --- harness layout ---
[ -d "$ROOT/.bare" ]                && record PASS "bare-repo"    ".bare/ found at $ROOT" \
                                    || record FAIL "bare-repo"    ".bare/ missing — run /my-harness-init or /my-harness-adopt"
[ -f "$ROOT/.my-harness/.config" ]  && record PASS "config"       "$ROOT/.my-harness/.config present" \
                                    || record FAIL "config"       ".my-harness/.config missing"

# --- MAX_LANES vs recommendation ---
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
  command -v "$tool" >/dev/null 2>&1 \
    && record PASS "tool-$tool"  "$(command -v "$tool")" \
    || record FAIL "tool-$tool"  "$tool not on PATH"
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
    # Cheapest auth probe: ~/.codex/auth.json must exist and be non-empty.
    if [ -s "$HOME/.codex/auth.json" ]; then
      record PASS "codex-auth" "~/.codex/auth.json present"
    else
      record FAIL "codex-auth" "~/.codex/auth.json missing — run: codex login"
    fi
  else
    record FAIL "codex-cli" "codex not on PATH but USE_CODEX_*=yes — install or set USE_CODEX=no"
  fi
fi

# --- Codex daemon ---
if [ -f "$ROOT/.my-harness/codex-app-server.pid" ]; then
  PID=$(cat "$ROOT/.my-harness/codex-app-server.pid" 2>/dev/null)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    record PASS "codex-daemon" "running (pid=$PID)"
  else
    record WARN "codex-daemon" "stale pid file (pid=$PID not running)"
  fi
fi

# --- spawn-lane-decision dry run for lane 1 ---
SPAWN="$ROOT/.my-harness/scripts/../../skills/harness-team-lead/scripts/spawn-lane-decision.sh"
[ -f "$SPAWN" ] || SPAWN="$(dirname "$0")/../skills/harness-team-lead/scripts/spawn-lane-decision.sh"
if [ -f "$SPAWN" ]; then
  D=$(bash "$SPAWN" 1 "$ROOT" 2>/dev/null | awk -F= '$1=="DECISION"{print $2; exit}')
  case "$D" in
    SPAWN|SKIP) record PASS "lane-gate" "lane-1 → $D" ;;
    REFUSE)     record WARN "lane-gate" "lane-1 → REFUSE (see spawn-lane-decision output)" ;;
    *)          record WARN "lane-gate" "spawn-lane-decision returned no DECISION" ;;
  esac
fi

# --- environment env-vars ---
[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" = "1" ] \
  && record PASS "agent-teams-env" "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1" \
  || record WARN "agent-teams-env" "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS not set — /harness-team-lead will fail"

# --- output ---
if [ "$JSON" -eq 1 ]; then
  printf '{"pass":%d,"fail":%d,"warn":%d,"checks":[' "$PASS" "$FAIL" "$WARN"
  first=1
  echo "$RESULTS" | while IFS='|' read -r kind name msg; do
    [ -z "$kind" ] && continue
    [ "$first" -eq 0 ] && printf ','
    printf '{"kind":"%s","name":"%s","msg":"%s"}' "$kind" "$name" "$(printf '%s' "$msg" | sed 's/"/\\"/g')"
    first=0
  done
  echo ']}'
else
  echo "$RESULTS" | while IFS='|' read -r kind name msg; do
    [ -z "$kind" ] && continue
    case "$kind" in
      PASS) sym="✓" ;;
      FAIL) sym="✗" ;;
      WARN) sym="!" ;;
    esac
    printf '%s %-20s %s\n' "$sym" "$name" "$msg"
  done
  echo
  echo "summary: $PASS pass, $FAIL fail, $WARN warn"
fi

[ "$FAIL" -gt 0 ] && exit 1
[ "$WARN" -gt 0 ] && exit 2
exit 0
