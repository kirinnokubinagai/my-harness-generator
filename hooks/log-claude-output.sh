#!/usr/bin/env bash
# Summary: Called by the Claude Code Stop hook. Extracts Claude's last response from the
#          transcript and appends it (masked) to <project>/dev/docs/talk/<date>.md.
#
# Official stdin JSON schema:
#   {
#     "session_id": "...",
#     "transcript_path": "...",   <- extract last assistant message from this jsonl
#     "cwd": "...",
#     "permission_mode": "...",
#     "hook_event_name": "Stop",
#     "stop_hook_active": false
#   }

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

TRANSCRIPT_PATH=""
WORK_DIR=""
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
  WORK_DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
fi
[ -z "$WORK_DIR" ] && WORK_DIR="${PWD:-$(pwd)}"

PROJECT_ROOT="$WORK_DIR"
while [ "$PROJECT_ROOT" != "/" ] && [ "$PROJECT_ROOT" != "" ]; do
  [ -f "$PROJECT_ROOT/.my-harness/.config" ] && break
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
[ -f "$PROJECT_ROOT/.my-harness/.config" ] || exit 0

[ -f "$TRANSCRIPT_PATH" ] || exit 0

HARNESS_GENERATOR_DIR="${CLAUDE_PLUGIN_ROOT:-${HARNESS_GENERATOR_DIR:-$HOME/my-harness-generator}}"
MASK="$HARNESS_GENERATOR_DIR/scripts/mask-secrets.sh"

# Extract the last assistant message text from the transcript jsonl
LAST_TEXT=""
if command -v jq >/dev/null 2>&1; then
  LAST_TEXT=$(jq -r '
    select(.type == "assistant" or .role == "assistant")
    | (.message.content // .content // .text // empty)
    | if type == "array" then map(select(.type == "text") | .text) | join("\n") else . end
  ' "$TRANSCRIPT_PATH" 2>/dev/null | grep -v '^$' | tail -1)
fi
[ -z "$LAST_TEXT" ] && exit 0

if [ -x "$MASK" ]; then
  MASKED=$(printf '%s' "$LAST_TEXT" | bash "$MASK" 2>/dev/null || printf '%s' "$LAST_TEXT")
else
  MASKED="$LAST_TEXT"
fi

# Same dev/ vs worktree-already-resolved logic as log-user-prompt.sh:
# bootstrap.sh writes .my-harness/.config at BOTH project root and inside each
# worktree, so the walk-up may stop on the inner copy. Skip the /dev/ prefix
# in that case to avoid `<root>/dev/dev/docs/talk` paths.
PARENT_DIR="$(dirname "$PROJECT_ROOT")"
if [ -f "$PARENT_DIR/.my-harness/.config" ]; then
  TALK_BASE="$PROJECT_ROOT/docs/talk"
else
  TALK_BASE="$PROJECT_ROOT/dev/docs/talk"
fi

DATE_STR=$(date +%Y-%m-%d)
TIME_STR=$(date +%H:%M:%S)
TALK_FILE="$TALK_BASE/${DATE_STR}.md"
mkdir -p "$(dirname "$TALK_FILE")" 2>/dev/null || exit 0
{
  printf '\n## %s - Claude\n\n' "$TIME_STR"
  printf '%s\n' "$MASKED"
} >> "$TALK_FILE" 2>/dev/null || true

exit 0
