#!/usr/bin/env bash
# ensure-hermes-config.sh — capture Hermes Agent Discord bot token,
# voice settings, AI provider, and Discord channel names for the OCI VM.
# Saves to .my-harness/.hermes-config.json (chmod 600).
#
# Usage:
#   bash ensure-hermes-config.sh <root> [<discord-bot-token>] [<hermes-ai-provider>] [<openai-key-if-codex>] [<home-channel-name>] [<app-channel-name>]
#
#   root               = project root containing .my-harness/
#   discord-bot-token  = Discord bot token (MT[A-Za-z0-9_.-]{50,})
#   hermes-ai-provider = "codex" or "gemma4"
#   openai-key         = OpenAI API key (sk-...) — required when provider=codex
#   home-channel-name  = Discord channel for proactive messages (e.g. #bot-updates)
#                        Shape: ^#[a-z0-9_-]{1,99}$
#   app-channel-name   = Discord channel for user conversations (e.g. #bot-chat)
#                        Shape: ^#[a-z0-9_-]{1,99}$
#
# Exit codes:
#   0 — config saved to .my-harness/.hermes-config.json (chmod 600)
#   1 — validation failed (bad token shape, unsupported provider, missing key,
#       or invalid channel name shape)
#   2 — token failed regex validation
#   3 — no arguments provided; caller (SKILL.md) should AskUserQuestion
#
# Pattern mirrors ensure-notification-webhook.sh / ensure-codex-auth.sh.

set -u

ROOT="${1:-}"
DISCORD_BOT_TOKEN="${2:-}"
HERMES_AI_PROVIDER="${3:-}"
OPENAI_API_KEY_ARG="${4:-}"
HOME_CHANNEL_NAME_ARG="${5:-}"
APP_CHANNEL_NAME_ARG="${6:-}"

# No arguments at all → signal to SKILL.md to use AskUserQuestion.
if [ -z "$ROOT" ] && [ -z "$DISCORD_BOT_TOKEN" ]; then
  echo "::error:: no arguments provided. Caller (SKILL.md) should AskUserQuestion to obtain required values, then re-invoke." >&2
  exit 3
fi

# Both channel args empty (and not yet saved) → signal caller to AskUserQuestion for them.
# We defer this check until after ROOT is set so we can inspect the existing JSON.

ROOT="${ROOT:?root required (project root containing .my-harness/)}"

OUT="$ROOT/.my-harness/.hermes-config.json"

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

validate_token() {
  local token="$1"
  if [ -z "$token" ]; then
    echo "::error:: Discord bot token is empty." >&2
    return 2
  fi
  # Discord bot tokens look like: MTxxxxxxxx.xxxxxx.xxxxxxxxxxxxxxxx
  # They start with MT (base64 of the bot user ID) and are 50+ chars total.
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
    codex|gemma4) return 0 ;;
    claude)
      echo "::error:: HERMES_AI_PROVIDER=claude is not supported." >&2
      echo "  Hermes Agent requires an OpenAI-compatible endpoint." >&2
      echo "  Choose 'codex' (OpenAI API / ChatGPT Plus) or 'gemma4' (local Ollama)." >&2
      return 1
      ;;
    "")
      echo "::error:: HERMES_AI_PROVIDER is empty. Choose 'codex' or 'gemma4'." >&2
      return 1
      ;;
    *)
      echo "::error:: Unknown HERMES_AI_PROVIDER='$provider'. Choose 'codex' or 'gemma4'." >&2
      return 1
      ;;
  esac
}

validate_openai_key() {
  local key="$1"
  if [ -z "$key" ]; then
    echo "::error:: OPENAI_API_KEY is required when HERMES_AI_PROVIDER=codex." >&2
    echo "  Obtain one at: https://platform.openai.com/api-keys" >&2
    return 1
  fi
  if ! echo "$key" | grep -qE '^sk-'; then
    echo "::error:: OPENAI_API_KEY should start with 'sk-'. Got: '${key:0:8}...'" >&2
    return 1
  fi
  return 0
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
    echo "  Examples: #bot-updates  #hermes-home  #bot_chat" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------

validate_token "$DISCORD_BOT_TOKEN" || exit 2
validate_provider "$HERMES_AI_PROVIDER" || exit 1

validate_channel_name "$HOME_CHANNEL_NAME_ARG" "home" || exit 1
validate_channel_name "$APP_CHANNEL_NAME_ARG"  "app"  || exit 1

OPENAI_API_KEY_VAL=""
OPENAI_BASE_URL=""
OPENAI_MODEL=""

case "$HERMES_AI_PROVIDER" in
  codex)
    validate_openai_key "$OPENAI_API_KEY_ARG" || exit 1
    OPENAI_API_KEY_VAL="$OPENAI_API_KEY_ARG"
    OPENAI_BASE_URL="https://api.openai.com/v1"
    OPENAI_MODEL="gpt-4o"
    ;;
  gemma4)
    OPENAI_API_KEY_VAL=""   # Ollama doesn't require an API key
    OPENAI_BASE_URL="http://localhost:11434/v1"
    OPENAI_MODEL="gemma4:e4b"
    ;;
esac

# ---------------------------------------------------------------------------
# Merge channel names: if arg is empty, preserve existing saved value.
# Mirrors the GH_TOKEN merge pattern from ensure-notification-webhook.sh.
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
  echo "  Caller (SKILL.md) should AskUserQuestion for home_channel_name (Q12.9) and app_channel_name (Q12.10)." >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# Write .my-harness/.hermes-config.json (chmod 600)
# ---------------------------------------------------------------------------

python3 - <<PYEOF
import json, sys

config = {
    "_comment": "Auto-written by scripts/ensure-hermes-config.sh — do not edit by hand.",
    "_refresh": "Re-run scripts/ensure-hermes-config.sh to rotate the bot token or change provider.",
    "DISCORD_BOT_TOKEN": "$DISCORD_BOT_TOKEN",
    "HERMES_AI_PROVIDER": "$HERMES_AI_PROVIDER",
    "OPENAI_API_KEY": "$OPENAI_API_KEY_VAL",
    "OPENAI_BASE_URL": "$OPENAI_BASE_URL",
    "OPENAI_MODEL": "$OPENAI_MODEL",
    "discord": {
        "bot_token": "$DISCORD_BOT_TOKEN",
        "home_channel_name": "$HOME_CHANNEL_NAME_VAL",
        "app_channel_name": "$APP_CHANNEL_NAME_VAL",
    },
}

with open("$OUT", "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")

print("[hermes-config] wrote $OUT")
PYEOF

chmod 600 "$OUT"

echo "[hermes-config] saved Hermes Agent config to $OUT (chmod 600)"
echo "  Provider:        $HERMES_AI_PROVIDER"
echo "  Model:           $OPENAI_MODEL"
echo "  Base URL:        $OPENAI_BASE_URL"
echo "  Bot token:       ${DISCORD_BOT_TOKEN:0:8}...(truncated)"
echo "  Home channel:    $HOME_CHANNEL_NAME_VAL"
echo "  App channel:     $APP_CHANNEL_NAME_VAL"
