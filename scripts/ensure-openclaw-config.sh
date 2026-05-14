#!/usr/bin/env bash
# ensure-openclaw-config.sh — capture OpenClaw Discord bot token,
# AI provider, and Discord channel names for the OCI VM.
# Saves to .my-harness/.openclaw-config.json (chmod 600).
#
# Usage:
#   bash ensure-openclaw-config.sh <root> [<discord-bot-token>] [<openclaw-ai-provider>] [<provider-credential>] [<home-channel-name>] [<app-channel-name>] [<model>]
#
#   root                 = project root containing .my-harness/
#   discord-bot-token    = Discord bot token (MT[A-Za-z0-9_.-]{50,})
#   openclaw-ai-provider = "codex" | "claude-code" | "openrouter" | "claude-api"
#   provider-credential  = provider-specific credential:
#                            codex:       empty — uses ~/.codex/auth.json (ensure-codex-auth.sh)
#                            claude-code: empty — uses ~/.claude/.credentials.json (ensure-codex-auth.sh)
#                            openrouter:  sk-or-... (OpenRouter API key)
#                            claude-api:  sk-ant-api... (Anthropic API key, NOT OAuth sk-ant-oat01-...)
#   home-channel-name    = Discord channel for proactive messages (e.g. #bot-updates)
#                          Shape: ^#[a-z0-9_-]{1,99}$
#   app-channel-name     = Discord channel for user conversations (e.g. #bot-chat)
#                          Shape: ^#[a-z0-9_-]{1,99}$
#   model                = LLM model ID (e.g. gpt-5.4-mini, claude-sonnet-4-6).
#                          If empty, a sensible default is chosen per provider.
#
# Exit codes:
#   0 — config saved to .my-harness/.openclaw-config.json (chmod 600)
#   1 — validation failed (bad token shape, unsupported provider, missing/wrong key,
#       or invalid channel name shape)
#   2 — token failed regex validation
#   3 — no arguments provided; caller (SKILL.md) should AskUserQuestion
#
# Pattern mirrors ensure-hermes-config.sh.

set -u

ROOT="${1:-}"
DISCORD_BOT_TOKEN="${2:-}"
OPENCLAW_AI_PROVIDER="${3:-}"
PROVIDER_CREDENTIAL_ARG="${4:-}"
HOME_CHANNEL_NAME_ARG="${5:-}"
APP_CHANNEL_NAME_ARG="${6:-}"
MODEL_ARG="${7:-}"

# No arguments at all → signal to SKILL.md to use AskUserQuestion.
if [ -z "$ROOT" ] && [ -z "$DISCORD_BOT_TOKEN" ]; then
  echo "::error:: no arguments provided. Caller (SKILL.md) should AskUserQuestion to obtain required values, then re-invoke." >&2
  exit 3
fi

ROOT="${ROOT:?root required (project root containing .my-harness/)}"

OUT="$ROOT/.my-harness/.openclaw-config.json"

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

validate_token() {
  local token="$1"
  if [ -z "$token" ]; then
    echo "::error:: Discord bot token is empty." >&2
    return 2
  fi
  # Discord bot tokens: MTxxxxxxxx.xxxxxx.xxxxxxxxxxxxxxxx
  # Start with MT (base64 of the bot user ID), 50+ chars total.
  if ! echo "$token" | grep -qE '^MT[A-Za-z0-9_.-]{50,}'; then
    echo "::error:: Discord bot token shape looks wrong." >&2
    echo "  Expected: starts with 'MT' followed by 50+ alphanumeric/._- chars." >&2
    echo "  Got:      '${token:0:20}...' (length ${#token})" >&2
    echo "  Obtain a fresh token via: Discord Developer Portal → your app → Bot → Reset Token" >&2
    return 2
  fi
  return 0
}

validate_provider() {
  local provider="$1"
  case "$provider" in
    codex|claude-code|openrouter|claude-api) return 0 ;;
    claude)
      echo "::error:: OPENCLAW_AI_PROVIDER=claude is not supported." >&2
      echo "  Use 'claude-api' for Anthropic API key billing, or 'claude-code' for Claude Code CLI subscription via CLIProxyAPI." >&2
      return 1
      ;;
    gemma4)
      echo "::error:: OPENCLAW_AI_PROVIDER=gemma4 is not supported (RAM pressure on A1.Flex — same reason it was dropped from Hermes in 7.26.0)." >&2
      echo "  Choose one of: codex | claude-code | openrouter | claude-api" >&2
      return 1
      ;;
    "")
      echo "::error:: OPENCLAW_AI_PROVIDER is empty." >&2
      echo "  Choose one of: codex | claude-code | openrouter | claude-api" >&2
      return 1
      ;;
    *)
      echo "::error:: Unknown OPENCLAW_AI_PROVIDER='$provider'." >&2
      echo "  Choose one of: codex | claude-code | openrouter | claude-api" >&2
      return 1
      ;;
  esac
}

validate_provider_credential() {
  local provider="$1"
  local credential="$2"
  case "$provider" in
    codex)
      # No credential needed — CLIProxyAPI reads ~/.codex/auth.json automatically.
      if [ -n "$credential" ]; then
        echo "::warning:: OPENCLAW_AI_PROVIDER=codex uses ~/.codex/auth.json (deployed by ensure-codex-auth.sh)." >&2
        echo "  The provider-credential argument will be ignored for codex." >&2
      fi
      return 0
      ;;
    claude-code)
      # No credential needed — CLIProxyAPI reads ~/.claude/.credentials.json automatically.
      if [ -n "$credential" ]; then
        echo "::warning:: OPENCLAW_AI_PROVIDER=claude-code uses ~/.claude/.credentials.json (from claude setup-token)." >&2
        echo "  The provider-credential argument will be ignored for claude-code." >&2
      fi
      return 0
      ;;
    openrouter)
      if [ -z "$credential" ]; then
        echo "::error:: OPENCLAW_AI_PROVIDER=openrouter requires an OpenRouter API key (sk-or-...)." >&2
        echo "  Obtain one at: https://openrouter.ai/keys" >&2
        return 1
      fi
      if ! echo "$credential" | grep -qE '^sk-or-'; then
        echo "::error:: OpenRouter API key should start with 'sk-or-'. Got: '${credential:0:10}...'" >&2
        echo "  Obtain one at: https://openrouter.ai/keys" >&2
        return 1
      fi
      return 0
      ;;
    claude-api)
      if [ -z "$credential" ]; then
        echo "::error:: OPENCLAW_AI_PROVIDER=claude-api requires an Anthropic API key (sk-ant-api...)." >&2
        echo "  Obtain one at: https://console.anthropic.com/" >&2
        return 1
      fi
      # Anthropic API keys start with sk-ant-api (NOT sk-ant-oat01 which is the OAuth token).
      if ! echo "$credential" | grep -qE '^sk-ant-api'; then
        echo "::error:: Anthropic API key must start with 'sk-ant-api'. Got: '${credential:0:14}...'" >&2
        echo "  NOTE: 'sk-ant-oat01-...' is the OAuth token (for claude-code), not an API key." >&2
        echo "  Obtain a paid API key at: https://console.anthropic.com/" >&2
        return 1
      fi
      return 0
      ;;
  esac
}

# Discord channel name: ^#[a-z0-9_-]{1,99}$ (leading #, lowercase alnum+hyphen+underscore, 1-100 chars total)
validate_channel_name() {
  local name="$1"
  local label="$2"
  if [ -z "$name" ]; then
    return 0  # empty is OK — caller handles missing/merge logic
  fi
  if ! echo "$name" | grep -qE '^#[a-z0-9_-]{1,99}$'; then
    echo "::error:: $label channel name '$name' is invalid." >&2
    echo "  Expected format: #channel-name (leading '#', lowercase letters/digits/hyphens/underscores, 2-100 chars total)" >&2
    echo "  Examples: #bot-updates  #openclaw-home  #bot_chat" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------

validate_token "$DISCORD_BOT_TOKEN" || exit 2
validate_provider "$OPENCLAW_AI_PROVIDER" || exit 1
validate_provider_credential "$OPENCLAW_AI_PROVIDER" "$PROVIDER_CREDENTIAL_ARG" || exit 1

validate_channel_name "$HOME_CHANNEL_NAME_ARG" "home" || exit 1
validate_channel_name "$APP_CHANNEL_NAME_ARG"  "app"  || exit 1

# Provider-specific derived values written to the JSON config.
# codex / claude-code: CLIProxyAPI runs locally on port 8317 — no API key needed.
# openrouter:          direct connection; key goes in the JSON as openrouter_api_key.
# claude-api:          direct connection; key goes in the JSON as anthropic_api_key.
OPENROUTER_API_KEY_VAL=""
ANTHROPIC_API_KEY_VAL=""
OPENCLAW_BASE_URL=""
OPENCLAW_MODEL=""

case "$OPENCLAW_AI_PROVIDER" in
  codex)
    OPENCLAW_BASE_URL="http://localhost:8317/v1"
    OPENCLAW_MODEL="${MODEL_ARG:-gpt-5.4-mini}"
    ;;
  claude-code)
    OPENCLAW_BASE_URL="http://localhost:8317/v1"
    OPENCLAW_MODEL="${MODEL_ARG:-claude-sonnet-4-6}"
    ;;
  openrouter)
    OPENROUTER_API_KEY_VAL="$PROVIDER_CREDENTIAL_ARG"
    OPENCLAW_BASE_URL="https://openrouter.ai/api/v1"
    OPENCLAW_MODEL="${MODEL_ARG:-anthropic/claude-sonnet-4}"
    ;;
  claude-api)
    ANTHROPIC_API_KEY_VAL="$PROVIDER_CREDENTIAL_ARG"
    OPENCLAW_BASE_URL=""
    OPENCLAW_MODEL="${MODEL_ARG:-anthropic/claude-sonnet-4-6}"
    ;;
esac

# ---------------------------------------------------------------------------
# Merge channel names: if arg is empty, preserve existing saved value.
# Mirrors the pattern from ensure-hermes-config.sh.
# ---------------------------------------------------------------------------

mkdir -p "$ROOT/.my-harness"

HOME_CHANNEL_NAME_VAL="$HOME_CHANNEL_NAME_ARG"
APP_CHANNEL_NAME_VAL="$APP_CHANNEL_NAME_ARG"

if [ -f "$OUT" ]; then
  # Read existing values if present (gracefully handle missing keys).
  if [ -z "$HOME_CHANNEL_NAME_VAL" ]; then
    HOME_CHANNEL_NAME_VAL="$(python3 -c "import json; d=json.load(open('$OUT')); print(d.get('discord',{}).get('home_channel_name',''))" 2>/dev/null || true)"
  fi
  if [ -z "$APP_CHANNEL_NAME_VAL" ]; then
    APP_CHANNEL_NAME_VAL="$(python3 -c "import json; d=json.load(open('$OUT')); print(d.get('discord',{}).get('app_channel_name',''))" 2>/dev/null || true)"
  fi
fi

# Both channel names still empty after merge → signal caller to AskUserQuestion.
if [ -z "$HOME_CHANNEL_NAME_VAL" ] && [ -z "$APP_CHANNEL_NAME_VAL" ]; then
  echo "::error:: Discord channel names not provided and none saved previously." >&2
  echo "  Caller (SKILL.md) should AskUserQuestion for home_channel_name (Q12.5.9) and app_channel_name (Q12.5.10)." >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# Write .my-harness/.openclaw-config.json (chmod 600)
# ---------------------------------------------------------------------------

python3 - <<PYEOF
import json, sys

# Null-safe: empty string → JSON null for optional credentials.
def nullify(v):
    return v if v else None

config = {
    "_comment": "Auto-written by scripts/ensure-openclaw-config.sh — do not edit by hand.",
    "_refresh": "Re-run scripts/ensure-openclaw-config.sh to rotate the bot token or change provider.",
    "DISCORD_BOT_TOKEN": "$DISCORD_BOT_TOKEN",
    "OPENCLAW_AI_PROVIDER": "$OPENCLAW_AI_PROVIDER",
    "OPENCLAW_BASE_URL": "$OPENCLAW_BASE_URL",
    "OPENCLAW_MODEL": "$OPENCLAW_MODEL",
    # Per-provider credential slots (null when not applicable).
    "openrouter_api_key": nullify("$OPENROUTER_API_KEY_VAL"),
    "anthropic_api_key":  nullify("$ANTHROPIC_API_KEY_VAL"),
    "discord": {
        "bot_token": "$DISCORD_BOT_TOKEN",
        "home_channel_name": "$HOME_CHANNEL_NAME_VAL",
        "app_channel_name": "$APP_CHANNEL_NAME_VAL",
    },
    "ai_provider": "$OPENCLAW_AI_PROVIDER",
}

with open("$OUT", "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")

print("[openclaw-config] wrote $OUT")
PYEOF

chmod 600 "$OUT"

echo "[openclaw-config] saved OpenClaw config to $OUT (chmod 600)"
echo "  Provider:        $OPENCLAW_AI_PROVIDER"
echo "  Model:           $OPENCLAW_MODEL"
echo "  Base URL:        ${OPENCLAW_BASE_URL:-(native provider, no base_url)}"
echo "  Bot token:       ${DISCORD_BOT_TOKEN:0:8}...(truncated)"
echo "  Home channel:    $HOME_CHANNEL_NAME_VAL"
echo "  App channel:     $APP_CHANNEL_NAME_VAL"
