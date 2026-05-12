#!/usr/bin/env bats
# Tests for scripts/ensure-notification-webhook.sh — webhook persistence.

setup() {
  HARNESS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$HARNESS_DIR/scripts/ensure-notification-webhook.sh"
  TMPDIR_TEST="$(mktemp -d)"
  ROOT="$TMPDIR_TEST/proj"
  mkdir -p "$ROOT"
  OUT_FILE="$ROOT/.my-harness/.notification.env"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "rejects invalid service" {
  run bash "$SCRIPT" "$ROOT" "foobar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid service"* ]]
}

@test "service=none with prior config wipes .notification.env" {
  mkdir -p "$ROOT/.my-harness"
  printf 'NOTIFICATION_SERVICE=discord\nNOTIFICATION_WEBHOOK_URL=https://discord.com/api/webhooks/1/abc\n' > "$OUT_FILE"
  [ -f "$OUT_FILE" ]

  run bash "$SCRIPT" "$ROOT" "none"
  [ "$status" -eq 0 ]
  [ ! -f "$OUT_FILE" ]
  [[ "$output" == *"removed"* ]]
}

@test "service=none with no prior config exits 0 cleanly" {
  run bash "$SCRIPT" "$ROOT" "none"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no prior config"* ]]
}

@test "discord with valid URL writes file with chmod 600" {
  url="https://discord.com/api/webhooks/123456789012345678/AbCdEfGhIjKlMnOpQrStUvWxYz_01234567"
  run bash "$SCRIPT" "$ROOT" "discord" "$url"
  [ "$status" -eq 0 ]
  [ -f "$OUT_FILE" ]
  grep -q "NOTIFICATION_SERVICE=discord" "$OUT_FILE"
  grep -q "NOTIFICATION_WEBHOOK_URL=$url" "$OUT_FILE"

  # chmod 600 check — use stat for a portable, attribute-free numeric mode.
  # `ls -l` on macOS appends `@` (extended attrs) or `+` (ACL) which would
  # break a string match against "-rw-------".
  if mode="$(stat -f '%Lp' "$OUT_FILE" 2>/dev/null)"; then
    : # macOS / BSD form
  else
    mode="$(stat -c '%a' "$OUT_FILE")"   # GNU form
  fi
  [ "$mode" = "600" ]
}

@test "discord with malformed URL exits 2" {
  run bash "$SCRIPT" "$ROOT" "discord" "https://example.com/not-a-webhook"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Discord webhook URL"* ]]
  [ ! -f "$OUT_FILE" ]
}

@test "slack with valid URL writes file" {
  # NOTE: this is a synthetic fixture URL, not a real webhook. GitHub
  # Push Protection scans for real Slack tokens — we keep the parts
  # short and obviously placeholder to stay out of the false-positive
  # heuristic. The regex in ensure-notification-webhook.sh still passes.
  url="https://hooks.slack.com/services/TESTFAKE/BTESTFAKE/0placeholder000"
  run bash "$SCRIPT" "$ROOT" "slack" "$url"
  [ "$status" -eq 0 ]
  [ -f "$OUT_FILE" ]
  grep -q "NOTIFICATION_SERVICE=slack" "$OUT_FILE"
  grep -q "NOTIFICATION_WEBHOOK_URL=$url" "$OUT_FILE"
}

@test "teams with valid URL (outlook.office.com) writes file" {
  url="https://outlook.office.com/webhook/abc-def-ghi/IncomingWebhook/xyz/123"
  run bash "$SCRIPT" "$ROOT" "teams" "$url"
  [ "$status" -eq 0 ]
  [ -f "$OUT_FILE" ]
  grep -q "NOTIFICATION_SERVICE=teams" "$OUT_FILE"
}

@test "teams with valid URL (tenant.webhook.office.com) writes file" {
  url="https://acme.webhook.office.com/webhookb2/abc/IncomingWebhook/def/ghi"
  run bash "$SCRIPT" "$ROOT" "teams" "$url"
  [ "$status" -eq 0 ]
  [ -f "$OUT_FILE" ]
  grep -q "NOTIFICATION_SERVICE=teams" "$OUT_FILE"
}

@test "no URL provided exits 3 (signals AskUserQuestion needed)" {
  run bash "$SCRIPT" "$ROOT" "discord"
  [ "$status" -eq 3 ]
  [[ "$output" == *"AskUserQuestion"* ]]
  [ ! -f "$OUT_FILE" ]
}
