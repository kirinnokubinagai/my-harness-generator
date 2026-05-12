#!/usr/bin/env bats
# Tests for scripts/find-existing-state.sh — walks up from PWD looking
# for .my-harness/init-state.json. Used at /my-harness-init startup to
# detect resume-vs-fresh.

setup() {
  HARNESS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$HARNESS_DIR/scripts/find-existing-state.sh"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "exits 1 when no init-state.json anywhere up the tree" {
  cd "$TMPDIR_TEST"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "finds init-state.json in PWD (depth 0)" {
  mkdir -p "$TMPDIR_TEST/.my-harness"
  printf '{}\n' > "$TMPDIR_TEST/.my-harness/init-state.json"
  cd "$TMPDIR_TEST"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *".my-harness/init-state.json"* ]]
}

@test "finds init-state.json one directory up (depth 1)" {
  mkdir -p "$TMPDIR_TEST/.my-harness" "$TMPDIR_TEST/sub"
  printf '{}\n' > "$TMPDIR_TEST/.my-harness/init-state.json"
  cd "$TMPDIR_TEST/sub"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "finds init-state.json three directories up (depth 3)" {
  mkdir -p "$TMPDIR_TEST/.my-harness" "$TMPDIR_TEST/a/b/c"
  printf '{}\n' > "$TMPDIR_TEST/.my-harness/init-state.json"
  cd "$TMPDIR_TEST/a/b/c"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}
