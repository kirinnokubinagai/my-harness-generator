#!/usr/bin/env bash
# register-agent-daily-report.sh — register the daily-report cron job
# inside the Hermes (or OpenClaw, planned for 7.28.0) agent on the VM.
#
# Called by setup-oci-vm-nixos.sh and setup-oci-vm.sh AFTER hermes-agent.service
# is up. Idempotent: re-running re-registers with the same name, which Hermes
# treats as an update.
#
# Usage:
#   bash register-agent-daily-report.sh <root> <agent> <ssh-target> <ssh-key>
#
# Where:
#   <root>        — path to project root containing .my-harness/
#   <agent>       — hermes | openclaw
#   <ssh-target>  — opc@<ip>
#   <ssh-key>     — path to private key

set -eu

ROOT="${1:?root required (path to project root containing .my-harness/)}"
AGENT="${2:?agent required (hermes|openclaw)}"
SSH_TARGET="${3:?ssh-target required (opc@<ip>)}"
SSH_KEY="${4:?ssh-key required (path to private key)}"

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"

trap 'rc=$?; [ $rc -ne 0 ] && echo "::error:: register-agent-daily-report.sh failed at line $LINENO (exit $rc)" >&2' EXIT

case "$AGENT" in
  hermes)
    : ;;  # handled below
  openclaw)
    echo "::warning:: OpenClaw daily-report registration is planned for 7.28.0 — no-op for now" >&2
    exit 0
    ;;
  *)
    echo "::error:: unknown agent '$AGENT' (expected hermes|openclaw)" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Read config files
# ---------------------------------------------------------------------------
HERMES_CONFIG="$ROOT/.my-harness/.hermes-config.json"
NOTIF_FILE="$ROOT/.my-harness/.notification.env"

[ -f "$HERMES_CONFIG" ] || {
  echo "::error:: $HERMES_CONFIG missing — run scripts/ensure-hermes-config.sh first" >&2
  exit 1
}
[ -f "$NOTIF_FILE" ] || {
  echo "::error:: $NOTIF_FILE missing — run Phase 1 Q6-Q11 first" >&2
  exit 1
}

DISCORD_HOME_CHANNEL_NAME="$(python3 -c "import json; d=json.load(open('$HERMES_CONFIG')); print(d.get('discord',{}).get('home_channel_name','#daily-report'))")"

# Derive REPO_OWNER / REPO_NAME from git remote (same logic as setup-oci-vm*.sh).
if ! GIT_REMOTE_URL="$(git -C "$ROOT" remote get-url origin 2>/dev/null)"; then
  echo "::error:: no 'origin' git remote at $ROOT" >&2
  exit 1
fi
REPO_SLUG="$(echo "$GIT_REMOTE_URL" | sed -e 's|^git@github\.com:||' -e 's|^https://github\.com/||' -e 's|^ssh://git@github\.com/||' -e 's|\.git$||')"
REPO_OWNER="${REPO_SLUG%%/*}"
REPO_NAME="${REPO_SLUG#*/}"

if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ] || [ "$REPO_OWNER" = "$REPO_SLUG" ]; then
  echo "::error:: could not parse owner/repo from remote URL: $GIT_REMOTE_URL" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Render the prompt template (registration-time substitution)
# ---------------------------------------------------------------------------
PROMPT_TMPL="$HARNESS_DIR/templates/oracle-cloud/hermes-agent/prompts/daily-report.md"
[ -f "$PROMPT_TMPL" ] || {
  echo "::error:: prompt template $PROMPT_TMPL not found — harness layout broken" >&2
  exit 1
}

RENDERED_PROMPT="$(mktemp /tmp/daily-report-XXXXXX.md)"
trap 'rm -f "$RENDERED_PROMPT"; rc=$?; [ $rc -ne 0 ] && echo "::error:: register-agent-daily-report.sh failed at line $LINENO (exit $rc)" >&2' EXIT

python3 - <<PYEOF
with open("$PROMPT_TMPL") as f:
    content = f.read()
content = content.replace("{{REPO_OWNER}}", "$REPO_OWNER")
content = content.replace("{{REPO_NAME}}", "$REPO_NAME")
content = content.replace("{{DISCORD_HOME_CHANNEL_NAME}}", "$DISCORD_HOME_CHANNEL_NAME")
with open("$RENDERED_PROMPT", "w") as f:
    f.write(content)
PYEOF

echo "[register-daily-report] rendered prompt: REPO_OWNER=$REPO_OWNER REPO_NAME=$REPO_NAME CHANNEL=$DISCORD_HOME_CHANNEL_NAME"

# ---------------------------------------------------------------------------
# scp the rendered prompt to the VM
# ---------------------------------------------------------------------------
SSH_OPTS=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -i "$SSH_KEY")

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p ~/hermes-agent/prompts && chmod 750 ~/hermes-agent/prompts"
scp -q -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
  "$RENDERED_PROMPT" "$SSH_TARGET:~/hermes-agent/prompts/daily-report.md"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "chmod 600 ~/hermes-agent/prompts/daily-report.md"

echo "[register-daily-report] prompt deployed to ~/hermes-agent/prompts/daily-report.md"

# ---------------------------------------------------------------------------
# Register the Hermes cron job via the hermes CLI over SSH.
#
# Hermes cron registration command (verified against Hermes docs 2026-05-14):
#
#   hermes cronjob add \
#     --name       daily-report \
#     --schedule   "0 9 * * *" \
#     --prompt-file /home/opc/hermes-agent/prompts/daily-report.md \
#     --session-id  daily-report-<REPO_NAME>
#
# The gateway must be running before this call (hermes-agent.service is up).
# Idempotent: re-running with the same --name updates the existing job.
#
# If the Hermes CLI syntax has changed in a newer release, the equivalent
# JSON-RPC call to the local gateway (default port 8080) is:
#
#   curl -s -X POST http://localhost:8080/api/cronjobs \
#     -H "Content-Type: application/json" \
#     -d '{"name":"daily-report","schedule":"0 9 * * *",
#          "prompt_file":"/home/opc/hermes-agent/prompts/daily-report.md",
#          "session_id":"daily-report-'"$REPO_NAME"'"}'
#
# Verify against docs at first deploy:
#   https://hermes-agent.nousresearch.com/docs/user-guide/features/cron
#   https://hermes-agent.nousresearch.com/docs/guides/automate-with-cron
# ---------------------------------------------------------------------------
SESSION_ID="daily-report-${REPO_NAME}"

echo "[register-daily-report] registering Hermes cron job: name=daily-report schedule='0 9 * * *' session=$SESSION_ID"

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "export PATH=\"\$HOME/.hermes/bin:\$PATH\" && \
   hermes cronjob add \
     --name daily-report \
     --schedule '0 9 * * *' \
     --prompt-file /home/opc/hermes-agent/prompts/daily-report.md \
     --session-id '$SESSION_ID'" \
|| {
  echo "::warning:: 'hermes cronjob add' failed; falling back to JSON-RPC registration" >&2
  # Fallback: POST directly to the Hermes gateway API (port 8080).
  # Adjust the port if hermes-agent/config.yaml uses a non-default gateway port.
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
    "curl -sf -X POST http://localhost:8080/api/cronjobs \
       -H 'Content-Type: application/json' \
       -d '{\"name\":\"daily-report\",\"schedule\":\"0 9 * * *\",
            \"prompt_file\":\"/home/opc/hermes-agent/prompts/daily-report.md\",
            \"session_id\":\"$SESSION_ID\"}'" \
  || {
    echo "::error:: Hermes cron registration failed (both CLI and JSON-RPC). Check hermes-agent.service is running: journalctl -u hermes-agent -n 50" >&2
    exit 1
  }
  echo "[register-daily-report] cron registered via JSON-RPC fallback."
  exit 0
}

echo "[register-daily-report] Hermes cron job registered successfully."
echo "  name:       daily-report"
echo "  schedule:   0 9 * * * (= 09:00 UTC = 18:00 JST)"
echo "  session:    $SESSION_ID"
echo "  channel:    $DISCORD_HOME_CHANNEL_NAME"
echo "  prompt:     ~/hermes-agent/prompts/daily-report.md"
