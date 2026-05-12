#!/usr/bin/env bats
# Tests for scripts/ensure-codex-project-trust.sh — appends
# [projects."<root>"] trust_level = "trusted" to ~/.codex/config.toml.

setup() {
  HARNESS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$HARNESS_DIR/scripts/ensure-codex-project-trust.sh"
  TMPDIR_TEST="$(mktemp -d)"
  export CODEX_HOME="$TMPDIR_TEST/.codex"
  mkdir -p "$CODEX_HOME"
  # A fake project root that exists. We resolve to physical path because
  # ensure-codex-project-trust.sh internally uses `cd $ROOT && pwd -P`,
  # which on macOS turns /var/folders/... into /private/var/folders/...
  # (the underlying physical path of the /var symlink). The TOML section
  # it writes uses that physical path, so our assertions must match.
  mkdir -p "$TMPDIR_TEST/fake-project"
  FAKE_ROOT="$(cd "$TMPDIR_TEST/fake-project" && pwd -P)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "appends new project to empty config.toml" {
  run bash "$SCRIPT" "$FAKE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"added"* ]]
  grep -q "\[projects.\"$FAKE_ROOT\"\]" "$CODEX_HOME/config.toml"
  grep -q 'trust_level = "trusted"' "$CODEX_HOME/config.toml"
}

@test "is idempotent — second run reports already trusted" {
  bash "$SCRIPT" "$FAKE_ROOT"
  run bash "$SCRIPT" "$FAKE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already trusted"* ]]
  # Section should appear exactly once
  count=$(grep -c "\[projects.\"$FAKE_ROOT\"\]" "$CODEX_HOME/config.toml")
  [ "$count" -eq 1 ]
}

@test "preserves unrelated existing config sections" {
  cat > "$CODEX_HOME/config.toml" <<'EOF'
model_reasoning_effort = "xhigh"

[features]
custom_thing = true
EOF
  run bash "$SCRIPT" "$FAKE_ROOT"
  [ "$status" -eq 0 ]
  grep -q 'model_reasoning_effort = "xhigh"' "$CODEX_HOME/config.toml"
  grep -q '\[features\]' "$CODEX_HOME/config.toml"
  grep -q 'custom_thing = true' "$CODEX_HOME/config.toml"
  grep -q "\[projects.\"$FAKE_ROOT\"\]" "$CODEX_HOME/config.toml"
}

@test "does not overwrite an existing untrusted entry" {
  cat > "$CODEX_HOME/config.toml" <<EOF
[projects."$FAKE_ROOT"]
trust_level = "untrusted"
EOF
  run bash "$SCRIPT" "$FAKE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"trust_level != \"trusted\""* ]]
  grep -q 'trust_level = "untrusted"' "$CODEX_HOME/config.toml"
  ! grep -q 'trust_level = "trusted"' "$CODEX_HOME/config.toml"
}
