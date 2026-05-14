#!/usr/bin/env bash
# ai-provider.sh — single dispatch point for calling the configured AI
# provider with a prompt and receiving a plain-text response. Sourced
# from daily-progress.sh and event-watch.sh inside the OCI VM.
#
# Usage:
#   . "$SCRIPT_DIR/lib/ai-provider.sh"
#   text=$(ai_provider_run "your prompt here")
#
# Required env (loaded from .env by the caller):
#   AI_PROVIDER  — claude | codex | gemma4   (default: claude)
#
# Per-provider env requirements:
#   claude:   CLAUDE_CODE_OAUTH_TOKEN  (set by setup-oci-vm.sh from
#                                       .notification.env)
#   codex:    ~/.codex/auth.json       (transferred by setup-oci-vm.sh
#                                       from .my-harness/.codex-auth.json;
#                                       refresh token typically lasts
#                                       ~3 months, re-run `codex login`
#                                       on Mac when it expires).
#   gemma4:   Ollama daemon listening on $OLLAMA_URL (default
#                                       http://localhost:11434) with
#                                       model $GEMMA_MODEL pulled
#                                       (default gemma4:e4b). Both are
#                                       installed by setup-oci-vm.sh.

ai_provider_run() {
  local prompt="$1"
  case "${AI_PROVIDER:-claude}" in
    claude)
      : "${CLAUDE_CODE_OAUTH_TOKEN:?must be set when AI_PROVIDER=claude}"
      CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN" claude \
        -p "$prompt" --output-format text 2>/dev/null
      ;;
    codex)
      if [ ! -f "$HOME/.codex/auth.json" ]; then
        echo "::error:: ~/.codex/auth.json missing — run \`codex login\` on a desktop and re-run setup-oci-vm.sh to re-deploy auth." >&2
        return 1
      fi
      # `codex exec` is the documented non-interactive one-shot command.
      # If your installed codex version exposes it under a different
      # subcommand, override CODEX_EXEC_CMD in .env (e.g.
      # `CODEX_EXEC_CMD="codex run --prompt"`).
      local cmd="${CODEX_EXEC_CMD:-codex exec}"
      # shellcheck disable=SC2086
      $cmd "$prompt" 2>/dev/null
      ;;
    gemma4)
      local model="${GEMMA_MODEL:-gemma4:e4b}"
      local ollama_url="${OLLAMA_URL:-http://localhost:11434}"
      local payload
      payload=$(jq -nc --arg model "$model" --arg prompt "$prompt" \
        '{model:$model,prompt:$prompt,stream:false}')
      curl -sS --max-time 300 "$ollama_url/api/generate" -d "$payload" \
        | jq -r '.response // empty'
      ;;
    *)
      echo "::error:: unknown AI_PROVIDER '${AI_PROVIDER}' (expected: claude|codex|gemma4)" >&2
      return 2
      ;;
  esac
}
