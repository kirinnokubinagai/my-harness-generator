#!/usr/bin/env bats
# Tests for scripts/ensure-codex-effort.sh — model_reasoning_effort writer.

setup() {
  HARNESS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$HARNESS_DIR/scripts/ensure-codex-effort.sh"
  TMPDIR_TEST="$(mktemp -d)"
  export CODEX_HOME="$TMPDIR_TEST/.codex"
  mkdir -p "$CODEX_HOME"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "rejects invalid effort level" {
  run bash "$SCRIPT" ultrahigh
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid effort level"* ]]
}

@test "accepts every valid level" {
  for level in none minimal low medium high xhigh; do
    rm -f "$CODEX_HOME/config.toml"
    run bash "$SCRIPT" "$level"
    [ "$status" -eq 0 ]
  done
}

@test "writes the level to a missing config.toml (default xhigh)" {
  [ ! -f "$CODEX_HOME/config.toml" ]
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$CODEX_HOME/config.toml" ]
  grep -q 'model_reasoning_effort = "xhigh"' "$CODEX_HOME/config.toml"
}

@test "writes explicit level" {
  run bash "$SCRIPT" high
  [ "$status" -eq 0 ]
  grep -q 'model_reasoning_effort = "high"' "$CODEX_HOME/config.toml"
}

@test "is idempotent — existing value is preserved" {
  printf '%s\n' 'model_reasoning_effort = "medium"' > "$CODEX_HOME/config.toml"
  run bash "$SCRIPT" xhigh
  [ "$status" -eq 0 ]
  [[ "$output" == *"already set to 'medium'"* ]]
  grep -q 'model_reasoning_effort = "medium"' "$CODEX_HOME/config.toml"
  ! grep -q 'model_reasoning_effort = "xhigh"' "$CODEX_HOME/config.toml"
}

@test "inserts above [section] headers (top-level placement)" {
  cat > "$CODEX_HOME/config.toml" <<'EOF'
[features]
codex_app_server = true

[projects."/some/path"]
trust_level = "trusted"
EOF
  run bash "$SCRIPT" xhigh
  [ "$status" -eq 0 ]
  # First non-empty line must be the new top-level entry
  first_nonblank=$(grep -v '^[[:space:]]*$' "$CODEX_HOME/config.toml" | head -n1)
  [ "$first_nonblank" = 'model_reasoning_effort = "xhigh"' ]
}
