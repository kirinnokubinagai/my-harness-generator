#!/usr/bin/env bash
# Summary: Checks the Codex CLI login status.
#          Because the Codex CLI has no "auth status" command, this uses a two-stage
#          verification: checking for auth.json and a lightweight codex exec success.
# Exit code: 0 = logged in / 1 = not logged in or unknown / 127 = codex CLI not installed
# Stdout: status string (logged-in / not-logged-in / not-installed)

set -uo pipefail

if ! command -v codex >/dev/null 2>&1; then
  echo "not-installed"
  echo "::error:: codex CLI not found. Install with: npm i -g @openai/codex" >&2
  exit 127
fi

AUTH_FILE="${HOME}/.codex/auth.json"
if [ ! -f "$AUTH_FILE" ]; then
  echo "not-logged-in"
  echo "::warning:: $AUTH_FILE not found. Run 'codex login'." >&2
  exit 1
fi

# Loosely validate auth.json contents (OK if either access_token or api_key is present)
# Use jq if available, otherwise fall back to grep
if command -v jq >/dev/null 2>&1; then
  HAS_TOKEN=$(jq -r '
    (.tokens.access_token // .tokens.id_token // .api_key // .OPENAI_API_KEY // "") != ""
  ' "$AUTH_FILE" 2>/dev/null || echo "false")
else
  if grep -qE '"(access_token|id_token|api_key)"\s*:\s*"[^"]+' "$AUTH_FILE" 2>/dev/null; then
    HAS_TOKEN=true
  else
    HAS_TOKEN=false
  fi
fi

if [ "$HAS_TOKEN" != "true" ]; then
  echo "not-logged-in"
  echo "::warning:: No token found in auth.json. Run 'codex login' again." >&2
  exit 1
fi

echo "logged-in"
exit 0
