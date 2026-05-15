#!/usr/bin/env bash
# ai-provider.sh — single dispatch point for calling the configured AI
# model via CLIProxyAPI and receiving a plain-text response. Sourced
# from daily-progress.sh and event-watch.sh inside the OCI VM.
#
# Usage:
#   . "$SCRIPT_DIR/lib/ai-provider.sh"
#   text=$(ai_provider_run "your prompt here")
#
# Required env (loaded from .env by the caller):
#   AI_MODEL  — one of: claude-sonnet-4-6, claude-opus-4-7, claude-opus-4-6,
#               gpt-5.5, gpt-5.4-mini
#
# Both Claude and Codex models route through CLIProxyAPI (localhost:8317).
# The model name in the request determines which OAuth auth CLIProxyAPI uses:
#   claude-*  → uses ~/.claude/.credentials.json (Claude Pro/Max subscription)
#   gpt-*     → uses ~/.codex/auth.json (ChatGPT Plus/Pro subscription)
#
# Optional env:
#   CLIPROXY_URL — override CLIProxyAPI base URL (default: http://localhost:8317)

ai_provider_run() {
  local prompt="$1"
  : "${AI_MODEL:?must be set (one of claude-sonnet-4-6, claude-opus-4-7, claude-opus-4-6, gpt-5.5, gpt-5.4-mini)}"
  local proxy_url="${CLIPROXY_URL:-http://localhost:8317}"

  local payload
  payload=$(jq -nc \
    --arg model "$AI_MODEL" \
    --arg prompt "$prompt" \
    '{model: $model, messages: [{role: "user", content: $prompt}], stream: false}')

  local response
  response=$(curl -sS --max-time 300 "$proxy_url/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$payload")

  printf '%s' "$response" | jq -r '.choices[0].message.content // empty'
}
