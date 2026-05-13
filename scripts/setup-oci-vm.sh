#!/usr/bin/env bash
# setup-oci-vm.sh — bootstrap the daily-progress bot on a provisioned
# Oracle Cloud Always-Free VM.
#
# Prerequisites:
#   - scripts/ensure-notification-webhook.sh has been run
#   - scripts/ensure-github-pat.sh has been run
#   - scripts/ensure-oci-vm.sh has been run (writes .oci-vm.env)
#
# What this script does:
#   1. Loads .notification.env + .oci-vm.env
#   2. SSH-pings the VM
#   3. Installs Node LTS, gh, jq, curl, claude CLI on the VM
#   4. Reads CLAUDE_CODE_OAUTH_TOKEN from .my-harness/.notification.env
#      (populated by ensure-claude-oauth-token.sh — same value as the
#      `claude setup-token` output, ~1 year lifetime, no refresh needed)
#   5. Derives REPO_OWNER/REPO_NAME from `git remote get-url origin`
#   6. scp's templates/oracle-cloud/daily-progress-bot/ to the VM
#   7. Writes ~/daily-progress-bot/.env on the VM (chmod 600)
#   8. Runs daily-progress.sh once as a smoke test
#   9. Installs the crontab from crontab.example
#  10. Prints success summary
#
# Usage:
#   bash setup-oci-vm.sh <root>

set -u

ROOT="${1:?root required (path to project root containing .my-harness/)}"

trap 'rc=$?; if [ $rc -ne 0 ]; then echo "::error:: setup-oci-vm.sh failed at line $LINENO (exit $rc)" >&2; fi' EXIT

# -----------------------------------------------------------------------------
# Step 1: load both env files.
# -----------------------------------------------------------------------------
NOTIF_FILE="$ROOT/.my-harness/.notification.env"
OCI_FILE="$ROOT/.my-harness/.oci-vm.env"

if [ ! -f "$NOTIF_FILE" ]; then
  echo "::error:: $NOTIF_FILE not found — run ensure-notification-webhook.sh + ensure-github-pat.sh first" >&2
  exit 1
fi
if [ ! -f "$OCI_FILE" ]; then
  echo "::error:: $OCI_FILE not found — run ensure-oci-vm.sh first" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$NOTIF_FILE"
# shellcheck disable=SC1090
. "$OCI_FILE"
set +a

# Verify all required vars are present.
missing=()
for v in NOTIFICATION_SERVICE NOTIFICATION_WEBHOOK_URL GH_TOKEN CLAUDE_CODE_OAUTH_TOKEN \
         OCI_VM_NAME OCI_VM_REGION OCI_VM_INSTANCE_ID OCI_VM_PUBLIC_IP OCI_VM_SSH_KEY; do
  eval "val=\${$v:-}"
  [ -n "$val" ] || missing+=("$v")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "::error:: missing required env: ${missing[*]}" >&2
  case " ${missing[*]} " in
    *" CLAUDE_CODE_OAUTH_TOKEN "*)
      echo "  → run \`claude setup-token\` on this Mac, then \`bash ensure-claude-oauth-token.sh <root> <token>\` to save it." >&2
      ;;
  esac
  exit 1
fi

# Expand ~ in OCI_VM_SSH_KEY if persisted that way.
case "$OCI_VM_SSH_KEY" in
  "~/"*) OCI_VM_SSH_KEY="$HOME/${OCI_VM_SSH_KEY#~/}" ;;
esac

# -----------------------------------------------------------------------------
# Step 2: SSH connectivity test.
# -----------------------------------------------------------------------------
SSH_OPTS=(
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$HOME/.ssh/known_hosts"
  -i "$OCI_VM_SSH_KEY"
)
SSH_TARGET="opc@$OCI_VM_PUBLIC_IP"

echo "[setup-vm] testing SSH to $SSH_TARGET..."
# Discard stderr — ssh prints "Warning: Permanently added '...' to known hosts"
# on first connect, which would contaminate the strict "ok" string match below.
ssh_out="$(ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "echo ok" 2>/dev/null)" || {
  echo "::error:: SSH connectivity failed (re-running with stderr visible):" >&2
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "echo ok" >&2 || true
  echo "  Check: VM running, public IP reachable, security list allows port 22, key matches." >&2
  exit 2
}
if [ "$ssh_out" != "ok" ]; then
  echo "::error:: unexpected SSH echo response: '$ssh_out'" >&2
  exit 2
fi
echo "[setup-vm] SSH ok."

# -----------------------------------------------------------------------------
# Step 4: install dependencies on the VM. Heredoc-over-ssh.
# Oracle Linux 9 → dnf. Detect at run-time so the script also works if
# someone reuses it on an Ubuntu VM later.
# -----------------------------------------------------------------------------
echo "[setup-vm] installing dependencies on VM (Node LTS, gh, jq, curl, claude CLI)..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' <<'REMOTE_INSTALL'
set -eu

if command -v dnf >/dev/null 2>&1; then
  PKG=dnf
elif command -v apt-get >/dev/null 2>&1; then
  PKG=apt
else
  echo "::error:: unsupported package manager (need dnf or apt)" >&2
  exit 1
fi

if [ "$PKG" = "dnf" ]; then
  sudo dnf install -y curl jq tar gzip ca-certificates
  # Node.js 20 LTS via NodeSource
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    sudo dnf install -y nodejs
  fi
  # gh CLI
  if ! command -v gh >/dev/null 2>&1; then
    sudo dnf install -y dnf-command\(config-manager\) || true
    sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    sudo dnf install -y gh
  fi
else
  sudo apt-get update
  sudo apt-get install -y curl jq ca-certificates gnupg
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
  fi
  if ! command -v gh >/dev/null 2>&1; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update && sudo apt-get install -y gh
  fi
fi

# claude CLI under user-local npm prefix so we don't need sudo every install.
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
case ":$PATH:" in
  *":$HOME/.npm-global/bin:"*) : ;;
  *)
    {
      echo ''
      echo '# daily-progress-bot npm global bin'
      echo 'export PATH="$HOME/.npm-global/bin:$PATH"'
    } >> "$HOME/.bashrc"
    ;;
esac
export PATH="$HOME/.npm-global/bin:$PATH"

if ! command -v claude >/dev/null 2>&1; then
  npm install -g @anthropic-ai/claude-code
fi

echo "[remote] versions:"
node --version
npm --version
gh --version | head -n1
jq --version
claude --version || true
REMOTE_INSTALL

# -----------------------------------------------------------------------------
# Step 5: Claude OAuth token from .notification.env.
# The token is the value `claude setup-token` prints on a desktop Mac.
# It is saved by scripts/ensure-claude-oauth-token.sh into the same
# .notification.env that holds the webhook URL + GH_TOKEN. ~1 year
# lifetime, no refresh required, no Mac involvement after first save.
# This is the SAME token GitHub's claude-code-action consumes via
# `${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}` — one token, two consumers.
# -----------------------------------------------------------------------------
CLAUDE_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
echo "[setup-vm] Claude OAuth token from .notification.env: ${CLAUDE_TOKEN:0:14}... (length ${#CLAUDE_TOKEN})"

# -----------------------------------------------------------------------------
# Step 6: derive REPO_OWNER / REPO_NAME from git remote.
# -----------------------------------------------------------------------------
if ! GIT_REMOTE_URL="$(git -C "$ROOT" remote get-url origin 2>/dev/null)"; then
  echo "::error:: no 'origin' git remote in $ROOT" >&2
  echo "  Add one with: git -C $ROOT remote add origin <github-url>" >&2
  exit 4
fi

# Parse owner/repo from git@github.com:owner/repo.git or https://github.com/owner/repo(.git)
REPO_SLUG="$(echo "$GIT_REMOTE_URL" \
              | sed -e 's|^git@github\.com:||' \
                    -e 's|^https://github\.com/||' \
                    -e 's|^ssh://git@github\.com/||' \
                    -e 's|\.git$||')"

REPO_OWNER="${REPO_SLUG%%/*}"
REPO_NAME="${REPO_SLUG#*/}"

if [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ] || [ "$REPO_OWNER" = "$REPO_SLUG" ]; then
  echo "::error:: could not parse owner/repo from remote URL: $GIT_REMOTE_URL" >&2
  exit 4
fi
echo "[setup-vm] repo: $REPO_OWNER/$REPO_NAME"

# -----------------------------------------------------------------------------
# Step 7: scp the daily-progress-bot template.
# -----------------------------------------------------------------------------
LOCAL_BOT="$(cd "$(dirname "$0")/.." && pwd)/templates/oracle-cloud/daily-progress-bot"
if [ ! -d "$LOCAL_BOT" ]; then
  echo "::error:: $LOCAL_BOT not found — repo layout broken?" >&2
  exit 5
fi

echo "[setup-vm] copying $LOCAL_BOT → opc@$OCI_VM_PUBLIC_IP:~/daily-progress-bot/"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p ~/daily-progress-bot && chmod 700 ~/daily-progress-bot"
scp -r -o ConnectTimeout=10 \
       -o StrictHostKeyChecking=accept-new \
       -i "$OCI_VM_SSH_KEY" \
       "$LOCAL_BOT"/. "$SSH_TARGET:~/daily-progress-bot/"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "chmod +x ~/daily-progress-bot/*.sh"

# -----------------------------------------------------------------------------
# Step 8: write ~/daily-progress-bot/.env on the VM, chmod 600.
# -----------------------------------------------------------------------------
echo "[setup-vm] writing remote .env..."
# We feed the variables in via stdin (heredoc) so they don't appear on
# any process command line.
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' <<REMOTE_ENV
set -eu
umask 077
cat > "\$HOME/daily-progress-bot/.env" <<EOF
# Auto-written by scripts/setup-oci-vm.sh on \$(date -u +%Y-%m-%dT%H:%M:%SZ)
CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_TOKEN
NOTIFICATION_SERVICE=$NOTIFICATION_SERVICE
NOTIFICATION_WEBHOOK_URL=$NOTIFICATION_WEBHOOK_URL
GH_TOKEN=$GH_TOKEN
REPO_OWNER=$REPO_OWNER
REPO_NAME=$REPO_NAME
LANG_TAG=ja
LOOKBACK_HOURS=24
EOF
chmod 600 "\$HOME/daily-progress-bot/.env"
echo "[remote] .env written (chmod 600)"
REMOTE_ENV

# -----------------------------------------------------------------------------
# Step 9: smoke test — run daily-progress.sh once.
# -----------------------------------------------------------------------------
echo "[setup-vm] running smoke test (daily-progress.sh)..."
smoke_log="$(mktemp)"
trap 'rm -f "$smoke_log"' EXIT
if ! ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
       "export PATH=\$HOME/.npm-global/bin:\$PATH && ~/daily-progress-bot/daily-progress.sh" \
       > "$smoke_log" 2>&1; then
  echo "::error:: smoke test failed. VM-side log:" >&2
  sed 's/^/  /' "$smoke_log" >&2
  exit 6
fi
echo "[setup-vm] smoke test passed (output suppressed; check Discord/Slack/Teams channel)."

# -----------------------------------------------------------------------------
# Step 10: install crontab from crontab.example.
# -----------------------------------------------------------------------------
echo "[setup-vm] installing crontab..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' <<'REMOTE_CRON'
set -eu
if [ ! -f "$HOME/daily-progress-bot/crontab.example" ]; then
  echo "::error:: crontab.example missing on VM" >&2
  exit 1
fi
# Strip comments and empty lines from the example, keeping only real cron lines.
crontab "$HOME/daily-progress-bot/crontab.example"
echo "[remote] installed crontab:"
crontab -l
REMOTE_CRON

# -----------------------------------------------------------------------------
# Step 11: success summary.
# -----------------------------------------------------------------------------
cat <<EOF

[setup-vm] DONE.

  VM:       $OCI_VM_NAME ($OCI_VM_REGION)
  Public:   $OCI_VM_PUBLIC_IP
  SSH in:   ssh -i $OCI_VM_SSH_KEY opc@$OCI_VM_PUBLIC_IP
  Bot:      ~/daily-progress-bot/ on the VM
  Cron:     18:00 JST daily summary + hourly event watch
  Repo:     $REPO_OWNER/$REPO_NAME → $NOTIFICATION_SERVICE webhook

EOF
