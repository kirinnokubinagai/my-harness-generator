#!/usr/bin/env bash
# Smoke tests for skills/harness-team-lead/scripts/spawn-lane-decision.sh.
# No bats dependency — pure bash. Run from repo root: bash tests/spawn-lane-decision.sh

set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/skills/harness-team-lead/scripts/spawn-lane-decision.sh"
[ -f "$SCRIPT" ] || { echo "missing: $SCRIPT" >&2; exit 2; }

PASS=0; FAIL=0; LOG=""

assert() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS+1)); LOG="${LOG}✓ $name
"
  else
    FAIL=$((FAIL+1)); LOG="${LOG}✗ $name (expected '$expected', got '$actual')
"
  fi
}

decision_of() { awk -F= '$1=="DECISION"{print $2; exit}' <<<"$1"; }
reason_of()   { awk -F= '$1=="REASON"{print $2; exit}'   <<<"$1"; }

mk_root() {
  local r; r=$(mktemp -d)
  mkdir -p "$r/.bare" "$r/.my-harness"
  echo "$r"
}

# Override HOME so we never touch the real team config.
FAKE_HOME=$(mktemp -d)
export HOME="$FAKE_HOME"

# 1) invalid lane
out=$(bash "$SCRIPT" abc 2>&1)
assert "invalid-lane (non-numeric)" REFUSE "$(decision_of "$out")"

out=$(bash "$SCRIPT" 0 2>&1)
assert "invalid-lane (zero)" REFUSE "$(decision_of "$out")"

# 2) init-required when .config absent
ROOT=$(mk_root)
out=$(bash "$SCRIPT" 1 "$ROOT" 2>&1)
assert "init-required" REFUSE "$(decision_of "$out")"
case "$(reason_of "$out")" in init-required*) PASS=$((PASS+1)); LOG="${LOG}✓ init-required reason
" ;; *) FAIL=$((FAIL+1)); LOG="${LOG}✗ init-required reason mismatch
" ;; esac

# 3) MAX_LANES gate
ROOT=$(mk_root)
echo "MAX_LANES=2" > "$ROOT/.my-harness/.config"
out=$(bash "$SCRIPT" 3 "$ROOT" 2>&1)
assert "exceeds-max-lanes" REFUSE "$(decision_of "$out")"
case "$(reason_of "$out")" in exceeds-max-lanes*) PASS=$((PASS+1)); LOG="${LOG}✓ exceeds-max-lanes reason
" ;; *) FAIL=$((FAIL+1)); LOG="${LOG}✗ exceeds-max-lanes reason mismatch
" ;; esac

# 4) corrupt-team detection (suffixed names)
ROOT=$(mk_root)
echo "MAX_LANES=4" > "$ROOT/.my-harness/.config"
mkdir -p "$HOME/.claude/teams/harness-team"
cat > "$HOME/.claude/teams/harness-team/config.json" <<'JSON'
{"members":[{"name":"analyst-1-2"},{"name":"engineer-1"}]}
JSON
out=$(bash "$SCRIPT" 1 "$ROOT" 2>&1)
assert "corrupt-team" REFUSE "$(decision_of "$out")"
case "$(reason_of "$out")" in corrupt-team*) PASS=$((PASS+1)); LOG="${LOG}✓ corrupt-team reason
" ;; *) FAIL=$((FAIL+1)); LOG="${LOG}✗ corrupt-team reason mismatch
" ;; esac

# 5) SKIP when all four lane names already present
ROOT=$(mk_root)
echo "MAX_LANES=4" > "$ROOT/.my-harness/.config"
mkdir -p "$HOME/.claude/teams/harness-team"
cat > "$HOME/.claude/teams/harness-team/config.json" <<'JSON'
{"members":[
  {"name":"analyst-1"},{"name":"engineer-1"},
  {"name":"e2e-reviewer-1"},{"name":"reviewer-1"}
]}
JSON
out=$(bash "$SCRIPT" 1 "$ROOT" 2>&1)
assert "all-present-skip" SKIP "$(decision_of "$out")"

# 6) partial-lane detection (only some teammates present)
ROOT=$(mk_root)
echo "MAX_LANES=4" > "$ROOT/.my-harness/.config"
mkdir -p "$HOME/.claude/teams/harness-team"
cat > "$HOME/.claude/teams/harness-team/config.json" <<'JSON'
{"members":[{"name":"analyst-1"},{"name":"engineer-1"}]}
JSON
out=$(bash "$SCRIPT" 1 "$ROOT" 2>&1)
assert "partial-lane" REFUSE "$(decision_of "$out")"
case "$(reason_of "$out")" in partial-lane*) PASS=$((PASS+1)); LOG="${LOG}✓ partial-lane reason
" ;; *) FAIL=$((FAIL+1)); LOG="${LOG}✗ partial-lane reason mismatch
" ;; esac

printf '%s\n' "$LOG"
echo "----"
echo "$PASS pass, $FAIL fail"

rm -rf "$FAKE_HOME"
[ "$FAIL" -eq 0 ]
