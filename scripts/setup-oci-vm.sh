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
#   8.5 Installs /etc/logrotate.d/daily-progress so cron.log stays bounded
#       (rotated weekly, 4 weeks retained, gzip'd, copytruncate'd).
#   9. Installs the crontab from crontab.example
#  10. Prints success summary
#
# Usage:
#   bash setup-oci-vm.sh <root>

set -u

ROOT="${1:?root required (path to project root containing .my-harness/)}"

# Read OS_KIND from .notification.env (set by SKILL.md Q9.6). Default = nixos
# for new deployments; pass OS_KIND=oraclelinux explicitly to use the legacy
# dnf-based path below.
if [ -f "${ROOT}/.my-harness/.notification.env" ]; then
  OS_KIND=$(grep '^OS_KIND=' "${ROOT}/.my-harness/.notification.env" 2>/dev/null | cut -d= -f2)
fi
: "${OS_KIND:=nixos}"
case "$OS_KIND" in
  nixos)
    echo "[setup-vm] OS_KIND=nixos → handing off to setup-oci-vm-nixos.sh"
    exec bash "$(dirname "$0")/setup-oci-vm-nixos.sh" "$@"
    ;;
  oraclelinux|legacy) : ;;  # fall through to existing Oracle Linux logic
  *) echo "::error:: unknown OS_KIND='$OS_KIND' (expected nixos|oraclelinux)" >&2; exit 1 ;;
esac

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

: "${AI_PROVIDER:=claude}"
case "$AI_PROVIDER" in
  claude|codex|gemma4) : ;;
  *) echo "::error:: unknown AI_PROVIDER '$AI_PROVIDER' in $NOTIF_FILE (expected claude|codex|gemma4)" >&2; exit 1 ;;
esac
echo "[setup-vm] AI_PROVIDER=$AI_PROVIDER"

REQUIRED_VARS=(NOTIFICATION_SERVICE NOTIFICATION_WEBHOOK_URL GH_TOKEN \
               OCI_VM_NAME OCI_VM_REGION OCI_VM_INSTANCE_ID OCI_VM_PUBLIC_IP OCI_VM_SSH_KEY)
[ "$AI_PROVIDER" = "claude" ] && REQUIRED_VARS+=(CLAUDE_CODE_OAUTH_TOKEN)

missing=()
for v in "${REQUIRED_VARS[@]}"; do
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
echo "[setup-vm] installing dependencies on VM (Node LTS, gh, jq, curl, AI CLI)..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "AI_PROVIDER='$AI_PROVIDER' bash -s" <<'REMOTE_INSTALL'
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

# AI CLI under user-local npm prefix so we don't need sudo every install.
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

case "$AI_PROVIDER" in
  claude)
    echo "[remote] installing Claude Code CLI..."
    npm install -g @anthropic-ai/claude-code
    ;;
  codex)
    echo "[remote] installing Codex CLI..."
    npm install -g @openai/codex
    mkdir -p "$HOME/.codex"
    ;;
  gemma4)
    echo "[remote] installing Ollama + pulling gemma4:e4b..."
    if ! command -v ollama >/dev/null 2>&1; then
      curl -fsSL https://ollama.com/install.sh | sh
    fi
    sudo systemctl enable --now ollama || true
    # Wait for daemon up to 30s
    for i in $(seq 1 30); do
      curl -sS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1 && break
      sleep 1
    done
    if ! curl -sS http://localhost:11434/api/tags >/dev/null 2>&1; then
      echo "::error:: Ollama daemon did not come up within 30s" >&2
      exit 1
    fi
    ollama pull gemma4:e4b
    ;;
esac

echo "[remote] versions:"
node --version 2>/dev/null || true
case "$AI_PROVIDER" in
  claude) claude --version 2>/dev/null || true ;;
  codex)  codex --version 2>/dev/null || true ;;
  gemma4) ollama --version 2>/dev/null || true ;;
esac
REMOTE_INSTALL

# -----------------------------------------------------------------------------
# Step 4.5 — Transfer Codex auth.json when AI_PROVIDER=codex
# -----------------------------------------------------------------------------
if [ "$AI_PROVIDER" = "codex" ]; then
  CODEX_AUTH="$ROOT/.my-harness/.codex-auth.json"
  if [ ! -f "$CODEX_AUTH" ]; then
    echo "[setup-vm] Codex auth not yet captured — running ensure-codex-auth.sh..."
    HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
    if ! bash "$HARNESS_DIR/ensure-codex-auth.sh" "$ROOT"; then
      echo "::error:: ensure-codex-auth.sh failed — cannot deploy AI_PROVIDER=codex" >&2
      exit 3
    fi
  fi
  echo "[setup-vm] copying Codex auth to VM..."
  scp -q -i "$OCI_VM_SSH_KEY" -o StrictHostKeyChecking=accept-new \
    "$CODEX_AUTH" "$SSH_TARGET:~/.codex/auth.json"
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "chmod 600 ~/.codex/auth.json && ls -la ~/.codex/auth.json"
fi

# -----------------------------------------------------------------------------
# Step 5: Claude OAuth token from .notification.env.
# The token is the value `claude setup-token` prints on a desktop Mac.
# It is saved by scripts/ensure-claude-oauth-token.sh into the same
# .notification.env that holds the webhook URL + GH_TOKEN. ~1 year
# lifetime, no refresh required, no Mac involvement after first save.
# This is the SAME token GitHub's claude-code-action consumes via
# `${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}` — one token, two consumers.
# -----------------------------------------------------------------------------
if [ "$AI_PROVIDER" = "claude" ]; then
  CLAUDE_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
  echo "[setup-vm] Claude OAuth token from .notification.env: ${CLAUDE_TOKEN:0:14}... (length ${#CLAUDE_TOKEN})"
fi

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
AI_PROVIDER=$AI_PROVIDER
$([ "$AI_PROVIDER" = "claude" ] && echo "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_TOKEN")
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
# Step 8.5 — Install logrotate config (Oracle Linux path).
# Keeps /home/opc/daily-progress-bot/cron.log from growing unbounded.
# NixOS deployments (7.24.0+) use services.logrotate.settings instead;
# this branch only runs on the dnf-based VM (= current path).
# -----------------------------------------------------------------------------
LOGROTATE_SRC="$LOCAL_BOT/logrotate.conf"
if [ -f "$LOGROTATE_SRC" ]; then
  echo "[setup-vm] installing logrotate config for cron.log..."
  scp -q -i "$OCI_VM_SSH_KEY" -o StrictHostKeyChecking=accept-new \
    "$LOGROTATE_SRC" "$SSH_TARGET:/tmp/daily-progress.logrotate"
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' <<'REMOTE_LOGROTATE'
set -eu
sudo mkdir -p /var/log/daily-progress
sudo chown opc:opc /var/log/daily-progress
sudo chmod 750 /var/log/daily-progress
sudo install -o root -g root -m 0644 /tmp/daily-progress.logrotate /etc/logrotate.d/daily-progress
rm -f /tmp/daily-progress.logrotate
# Validate the config — logrotate -d does a dry run. If it errors, fail
# fast rather than silently shipping a broken config that gets picked up
# by /etc/cron.daily/logrotate next morning.
sudo /usr/sbin/logrotate -d /etc/logrotate.d/daily-progress >/dev/null 2>&1 || {
  echo "::error:: /etc/logrotate.d/daily-progress failed dry-run validation" >&2
  sudo /usr/sbin/logrotate -d /etc/logrotate.d/daily-progress >&2 || true
  exit 1
}
echo "[remote] logrotate installed: /etc/logrotate.d/daily-progress"
echo "[remote] rotated files will land in: /var/log/daily-progress/"
REMOTE_LOGROTATE
fi

# -----------------------------------------------------------------------------
# Hermes Agent deploy (Oracle Linux path — gated on HERMES_AGENT_ENABLED=yes)
# Set in .notification.env by /my-harness-init Q12.5.
# Supports 4 AI providers: codex | claude-code | openrouter | claude-api
# codex + claude-code route through CLIProxyAPI (localhost:8317).
# openrouter + claude-api connect directly with their respective API keys.
# -----------------------------------------------------------------------------
if [ "${HERMES_AGENT_ENABLED:-no}" = "yes" ]; then
  echo "[setup-vm] deploying Hermes Agent (Oracle Linux path)..."

  HERMES_CONFIG_LOCAL="$ROOT/.my-harness/.hermes-config.json"
  [ -f "$HERMES_CONFIG_LOCAL" ] || {
    echo "::error:: $HERMES_CONFIG_LOCAL missing — run scripts/ensure-hermes-config.sh first" >&2
    exit 1
  }

  HERMES_BOT_TOKEN="$(python3 -c "import json; d=json.load(open('$HERMES_CONFIG_LOCAL')); print(d['DISCORD_BOT_TOKEN'])")"
  HERMES_AI_PROVIDER_VAL="$(python3 -c "import json; d=json.load(open('$HERMES_CONFIG_LOCAL')); print(d['ai_provider'])")"
  HERMES_BASE_URL="$(python3 -c "import json; d=json.load(open('$HERMES_CONFIG_LOCAL')); print(d.get('OPENAI_BASE_URL',''))")"
  HERMES_MODEL="$(python3 -c "import json; d=json.load(open('$HERMES_CONFIG_LOCAL')); print(d['OPENAI_MODEL'])")"
  HERMES_OPENROUTER_KEY="$(python3 -c "import json; d=json.load(open('$HERMES_CONFIG_LOCAL')); print(d.get('openrouter_api_key') or '')")"
  HERMES_ANTHROPIC_KEY="$(python3 -c "import json; d=json.load(open('$HERMES_CONFIG_LOCAL')); print(d.get('anthropic_api_key') or '')")"
  DISCORD_HOME_CHANNEL_NAME="$(python3 -c "import json; d=json.load(open('$HERMES_CONFIG_LOCAL')); print(d.get('discord',{}).get('home_channel_name',''))")"
  DISCORD_APP_CHANNEL_NAME="$(python3 -c "import json; d=json.load(open('$HERMES_CONFIG_LOCAL')); print(d.get('discord',{}).get('app_channel_name',''))")"

  # Validate provider (gemma4 removed from Hermes in 7.26.0).
  case "$HERMES_AI_PROVIDER_VAL" in
    codex|claude-code|openrouter|claude-api) : ;;
    *)
      echo "::error:: Unsupported HERMES_AI_PROVIDER='$HERMES_AI_PROVIDER_VAL' in $HERMES_CONFIG_LOCAL" >&2
      echo "  Valid values: codex | claude-code | openrouter | claude-api" >&2
      exit 1 ;;
  esac

  HARNESS_DIR_VM="$(cd "$(dirname "$0")/.." && pwd)"

  # Build the provider YAML stanza for ${HERMES_PROVIDER_BLOCK}.
  case "$HERMES_AI_PROVIDER_VAL" in
    codex)
      HERMES_PROVIDER_BLOCK_OL="model:
  provider: custom
  default: hermes-codex-default
  base_url: http://localhost:8317/v1
  api_key: \"\""
      ;;
    claude-code)
      HERMES_PROVIDER_BLOCK_OL="model:
  provider: custom
  default: hermes-claude-default
  base_url: http://localhost:8317/v1
  api_key: \"\""
      ;;
    openrouter)
      HERMES_PROVIDER_BLOCK_OL="model:
  provider: openrouter
  default: anthropic/claude-sonnet-4
  # OPENROUTER_API_KEY is injected via .env (EnvironmentFile)"
      ;;
    claude-api)
      HERMES_PROVIDER_BLOCK_OL="model:
  provider: anthropic
  default: claude-sonnet-4-6
  # ANTHROPIC_API_KEY is injected via .env (EnvironmentFile)"
      ;;
  esac

  # Create directory structure on VM.
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p ~/hermes-agent/data && chmod 750 ~/hermes-agent"

  # Deploy CLIProxyAPI when needed (codex or claude-code provider).
  if [ "$HERMES_AI_PROVIDER_VAL" = "codex" ] || [ "$HERMES_AI_PROVIDER_VAL" = "claude-code" ]; then
    echo "[setup-vm] deploying CLIProxyAPI for provider=$HERMES_AI_PROVIDER_VAL (Oracle Linux path)..."

    # Render cliproxyapi config.
    CLIPROXY_TMPL="$HARNESS_DIR_VM/templates/oracle-cloud/cliproxyapi/config.example.yaml"
    RENDERED_CLIPROXY="$(mktemp /tmp/cliproxy-config-XXXXXX.yaml)"
    python3 - <<PYEOF
with open("$CLIPROXY_TMPL") as f:
    content = f.read()
enable_codex       = "$HERMES_AI_PROVIDER_VAL" == "codex"
enable_claude_code = "$HERMES_AI_PROVIDER_VAL" == "claude-code"
codex_excluded  = "" if enable_codex       else '- "*"'
claude_excluded = "" if enable_claude_code else '- "*"'
content = content.replace("\${CODEX_EXCLUDED}",  codex_excluded)
content = content.replace("\${CLAUDE_EXCLUDED}", claude_excluded)
with open("$RENDERED_CLIPROXY", "w") as f:
    f.write(content)
PYEOF

    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p ~/cliproxyapi && chmod 750 ~/cliproxyapi"
    scp -q -i "$OCI_VM_SSH_KEY" -o StrictHostKeyChecking=accept-new \
      "$RENDERED_CLIPROXY" "$SSH_TARGET:~/cliproxyapi/config.yaml"
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "chmod 600 ~/cliproxyapi/config.yaml"
    rm -f "$RENDERED_CLIPROXY"

    # Transfer Codex auth.json when provider=codex.
    if [ "$HERMES_AI_PROVIDER_VAL" = "codex" ]; then
      CODEX_AUTH="$ROOT/.my-harness/.codex-auth.json"
      [ -f "$CODEX_AUTH" ] || bash "$HARNESS_DIR_VM/scripts/ensure-codex-auth.sh" "$ROOT"
      scp -q -i "$OCI_VM_SSH_KEY" -o StrictHostKeyChecking=accept-new \
        "$CODEX_AUTH" "$SSH_TARGET:~/.codex/auth.json"
      ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "chmod 600 ~/.codex/auth.json"
    fi

    # Install CLIProxyAPI binary + systemd unit on Oracle Linux (no NixOS module).
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' <<'REMOTE_CLIPROXY_INSTALL'
set -eu
CLIPROXY_VERSION="7.0.6"
INSTALL_DIR="$HOME/cliproxyapi"
BIN="$INSTALL_DIR/cliproxyapi"
mkdir -p "$INSTALL_DIR"

if [ -x "$BIN" ] && "$BIN" --version 2>/dev/null | grep -q "$CLIPROXY_VERSION"; then
  echo "[remote] CLIProxyAPI v$CLIPROXY_VERSION already installed — skipping."
else
  echo "[remote] downloading CLIProxyAPI v$CLIPROXY_VERSION (linux/aarch64)..."
  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT
  curl -fsSL \
    "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${CLIPROXY_VERSION}/CLIProxyAPI_${CLIPROXY_VERSION}_linux_aarch64.tar.gz" \
    -o "$TMPDIR/cliproxyapi.tar.gz"
  tar -xzf "$TMPDIR/cliproxyapi.tar.gz" -C "$TMPDIR"
  EXTRACTED_BIN="$(find "$TMPDIR" -name 'CLIProxyAPI' -o -name 'cliproxyapi' | head -1)"
  [ -n "$EXTRACTED_BIN" ] || { echo "::error:: binary not found in tarball" >&2; exit 1; }
  install -m 0755 "$EXTRACTED_BIN" "$BIN"
  echo "[remote] CLIProxyAPI installed at $BIN"
fi

# Write systemd unit (Oracle Linux path).
sudo tee /etc/systemd/system/cliproxyapi.service >/dev/null <<UNIT
[Unit]
Description=CLIProxyAPI — local OpenAI-compatible proxy for Codex/Claude Code CLI subscriptions
After=network-online.target
Wants=network-online.target
Before=hermes-agent.service

[Service]
Type=simple
User=opc
Group=opc
WorkingDirectory=/home/opc/cliproxyapi
ExecStart=/home/opc/cliproxyapi/cliproxyapi --config /home/opc/cliproxyapi/config.yaml
Restart=on-failure
RestartSec=30s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cliproxyapi
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now cliproxyapi.service || {
  echo "::warning:: cliproxyapi.service failed to start; check: journalctl -u cliproxyapi -n 50" >&2
}
echo "[remote] cliproxyapi.service enabled and started."
REMOTE_CLIPROXY_INSTALL

  fi  # end CLIProxyAPI deploy

  # Render config.example.yaml → config.yaml (substitute placeholders).
  HERMES_TMPL="$HARNESS_DIR_VM/templates/oracle-cloud/hermes-agent/config.example.yaml"
  RENDERED_CONFIG="$(mktemp /tmp/hermes-config-XXXXXX.yaml)"
  python3 - <<PYEOF
with open("$HERMES_TMPL") as f:
    content = f.read()
replacements = {
    "\${HERMES_PROVIDER_BLOCK}":     """$HERMES_PROVIDER_BLOCK_OL""",
    "\${DISCORD_BOT_TOKEN}":         "$HERMES_BOT_TOKEN",
    "\${DISCORD_HOME_CHANNEL_NAME}": "$DISCORD_HOME_CHANNEL_NAME",
    "\${DISCORD_APP_CHANNEL_NAME}":  "$DISCORD_APP_CHANNEL_NAME",
}
for k, v in replacements.items():
    content = content.replace(k, v)
with open("$RENDERED_CONFIG", "w") as f:
    f.write(content)
PYEOF

  scp -q -i "$OCI_VM_SSH_KEY" -o StrictHostKeyChecking=accept-new \
    "$RENDERED_CONFIG" "$SSH_TARGET:~/hermes-agent/config.yaml"
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "chmod 600 ~/hermes-agent/config.yaml"
  rm -f "$RENDERED_CONFIG"

  # Write .env on VM (EnvironmentFile for hermes-agent.service).
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' <<REMOTE_HERMES_ENV_OL
set -eu
umask 077
{
  echo "# Auto-written by scripts/setup-oci-vm.sh — do not edit by hand."
  echo "DISCORD_BOT_TOKEN=$HERMES_BOT_TOKEN"
  echo "HERMES_AI_PROVIDER=$HERMES_AI_PROVIDER_VAL"
  echo "OPENAI_MODEL=$HERMES_MODEL"
  echo "DISCORD_HOME_CHANNEL_NAME=$DISCORD_HOME_CHANNEL_NAME"
  echo "DISCORD_APP_CHANNEL_NAME=$DISCORD_APP_CHANNEL_NAME"
$([ -n "$HERMES_OPENROUTER_KEY" ] && echo "  echo \"OPENROUTER_API_KEY=$HERMES_OPENROUTER_KEY\"" || true)
$([ -n "$HERMES_ANTHROPIC_KEY" ] && echo "  echo \"ANTHROPIC_API_KEY=$HERMES_ANTHROPIC_KEY\"" || true)
} > "\$HOME/hermes-agent/.env"
chmod 600 "\$HOME/hermes-agent/.env"
echo "[remote] hermes-agent .env written (chmod 600)"
REMOTE_HERMES_ENV_OL

  # Install Python 3, pip, ffmpeg if not present, then install Hermes.
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' <<'REMOTE_HERMES_INSTALL'
set -eu
# Ensure Python 3 + pip + ffmpeg (Oracle Linux 9 / dnf).
if ! command -v python3 >/dev/null 2>&1; then
  sudo dnf install -y python3 python3-pip
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  sudo dnf install -y ffmpeg || sudo dnf install -y ffmpeg-free || true
fi

HERMES_BIN="$HOME/.hermes/bin/hermes"
if [ ! -x "$HERMES_BIN" ]; then
  echo "[remote] installing Hermes Agent via official install.sh..."
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
fi

# Install voice + messaging extras (idempotent).
HERMES_PYTHON="$HOME/.hermes/venv/bin/python"
if [ -x "$HERMES_PYTHON" ]; then
  "$HERMES_PYTHON" -m pip install --quiet --upgrade \
    "hermes-agent[voice,messaging]" faster-whisper "neutts[all]" \
  || echo "[remote] pip install extras failed; core gateway may still work"
fi

# Symlink config so Hermes finds it.
mkdir -p "$HOME/.hermes"
[ -f "$HOME/hermes-agent/config.yaml" ] && \
  [ ! -f "$HOME/.hermes/config.yaml" ] && \
  ln -sf "$HOME/hermes-agent/config.yaml" "$HOME/.hermes/config.yaml" || true
[ -f "$HOME/hermes-agent/.env" ] && \
  [ ! -f "$HOME/.hermes/.env" ] && \
  ln -sf "$HOME/hermes-agent/.env" "$HOME/.hermes/.env" || true

echo "[remote] Hermes installed: $HERMES_BIN"
REMOTE_HERMES_INSTALL

  # Write systemd unit (Oracle Linux path — not managed by NixOS).
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' <<'REMOTE_HERMES_UNIT'
set -eu
sudo tee /etc/systemd/system/hermes-agent.service >/dev/null <<UNIT
[Unit]
Description=Hermes Agent — NousResearch personal AI gateway (Voice + Discord)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=opc
Group=opc
WorkingDirectory=/home/opc/hermes-agent
EnvironmentFile=/home/opc/hermes-agent/.env
ExecStart=/home/opc/.hermes/bin/hermes gateway start --foreground
Restart=on-failure
RestartSec=30s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=hermes-agent
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now hermes-agent.service || {
  echo "::warning:: hermes-agent.service failed to start; check: journalctl -u hermes-agent -n 50" >&2
}
echo "[remote] hermes-agent.service enabled and started."
REMOTE_HERMES_UNIT

  echo "[setup-vm] Hermes Agent deployed (Oracle Linux). First-run downloads ~575 MB of models; allow 5-10 min."
fi

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
