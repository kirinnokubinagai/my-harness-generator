#!/usr/bin/env bash
# ensure-hermes-config.sh — capture Hermes Agent Discord bot token,
# voice settings, and AI provider for the OCI VM. Saves to
# .my-harness/.hermes-config.json (chmod 600).
#
# Usage:
#   bash ensure-hermes-config.sh <root> [<discord-bot-token>] [<hermes-ai-provider>] [<openai-key-if-codex>]
#
#   root               = project root containing .my-harness/
#   discord-bot-token  = Discord bot token (MT[A-Za-z0-9_.-]{50,})
#   hermes-ai-provider = "codex" or "gemma4"
#   openai-key         = OpenAI API key (sk-...) — required when provider=codex
#
# Exit codes:
#   0 — config saved to .my-harness/.hermes-config.json (chmod 600)
#   1 — validation failed (bad token shape, unsupported provider, missing key)
#   2 — token failed regex validation
#   3 — no arguments provided; caller (SKILL.md) should AskUserQuestion
#
# Pattern mirrors ensure-notification-webhook.sh / ensure-codex-auth.sh.

set -u

ROOT="${1:-}"
DISCORD_BOT_TOKEN="${2:-}"
HERMES_AI_PROVIDER="${3:-}"
OPENAI_API_KEY_ARG="${4:-}"

# No arguments at all → signal to SKILL.md to use AskUserQuestion.
if [ -z "$ROOT" ] && [ -z "$DISCORD_BOT_TOKEN" ]; then
  echo "::error:: no arguments provided. Caller (SKILL.md) should AskUserQuestion to obtain required values, then re-invoke." >&2
  exit 3
fi

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

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------

validate_token "$DISCORD_BOT_TOKEN" || exit 2
validate_provider "$HERMES_AI_PROVIDER" || exit 1

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
# Write .my-harness/.hermes-config.json (chmod 600)
# ---------------------------------------------------------------------------

mkdir -p "$ROOT/.my-harness"

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
}

with open("$OUT", "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")

print("[hermes-config] wrote $OUT")
PYEOF

chmod 600 "$OUT"

echo "[hermes-config] saved Hermes Agent config to $OUT (chmod 600)"
echo "  Provider:   $HERMES_AI_PROVIDER"
echo "  Model:      $OPENAI_MODEL"
echo "  Base URL:   $OPENAI_BASE_URL"
echo "  Bot token:  ${DISCORD_BOT_TOKEN:0:8}...(truncated)"
