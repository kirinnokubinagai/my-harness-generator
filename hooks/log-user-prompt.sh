#!/usr/bin/env bash
# Summary: Called by the Claude Code UserPromptSubmit hook. Appends the user's input to
#          <project>/dev/docs/talk/<date>.md.
#          Sensitive values are always masked via mask-secrets.sh before writing.
#
# Official stdin JSON schema (from Claude Code Hooks reference):
#   {
#     "session_id": "...",
#     "transcript_path": "...",
#     "cwd": "...",
#     "permission_mode": "...",
#     "hook_event_name": "UserPromptSubmit",
#     "prompt": "user input text"
#   }
#
# Intended registration location (settings.json):
#   {
#     "hooks": {
#       "UserPromptSubmit": [
#         { "command": "bash <harness>/templates/hooks/log-user-prompt.sh" }
#       ]
#     }
#   }

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

# Extract prompt and cwd from JSON (use jq if available)
USER_PROMPT=""
WORK_DIR=""
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  USER_PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
  WORK_DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
fi
[ -z "$USER_PROMPT" ] && USER_PROMPT="$INPUT"
[ -z "$USER_PROMPT" ] && exit 0
[ -z "$WORK_DIR" ] && WORK_DIR="${PWD:-$(pwd)}"

# Locate project root (presence of .my-harness/.config). bootstrap.sh
# intentionally writes .my-harness/.config to BOTH the project root AND each
# worktree (dev/.my-harness/.config etc.) so harness scripts work whether
# run from outside or inside a worktree. Walk-up therefore stops at the
# nearest copy. Detect whether that copy belongs to the project root or
# to a worktree, so we don't accidentally write logs to dev/dev/docs/talk
# when running claude inside the dev/ worktree.
PROJECT_ROOT="$WORK_DIR"
while [ "$PROJECT_ROOT" != "/" ] && [ "$PROJECT_ROOT" != "" ]; do
  [ -f "$PROJECT_ROOT/.my-harness/.config" ] && break
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
[ -f "$PROJECT_ROOT/.my-harness/.config" ] || exit 0

HARNESS_GENERATOR_DIR="${CLAUDE_PLUGIN_ROOT:-${HARNESS_GENERATOR_DIR:-$HOME/my-harness-generator}}"
MASK="$HARNESS_GENERATOR_DIR/scripts/mask-secrets.sh"

if [ -x "$MASK" ]; then
  MASKED=$(printf '%s' "$USER_PROMPT" | bash "$MASK" 2>/dev/null || printf '%s' "$USER_PROMPT")
else
  MASKED="$USER_PROMPT"
fi

# Choose the talk directory based on whether PROJECT_ROOT is the outer
# project root or one of its worktrees (dev / stage / main):
#   <root>/.my-harness/.config       → talk lives at <root>/dev/docs/talk
#   <root>/dev/.my-harness/.config   → talk lives at <root>/dev/docs/talk too
# So if PROJECT_ROOT's parent ALSO has .my-harness/.config, we are inside a
# worktree and the dev/ prefix has already been consumed.
PARENT_DIR="$(dirname "$PROJECT_ROOT")"
if [ -f "$PARENT_DIR/.my-harness/.config" ]; then
  TALK_DIR="$PROJECT_ROOT/docs/talk"
else
  TALK_DIR="$PROJECT_ROOT/dev/docs/talk"
fi
mkdir -p "$TALK_DIR" 2>/dev/null || exit 0

DATE_STR=$(date +%Y-%m-%d)
TIME_STR=$(date +%H:%M:%S)
TALK_FILE="$TALK_DIR/${DATE_STR}.md"

{
  printf '\n## %s - User\n\n' "$TIME_STR"
  printf '%s\n' "$MASKED"
} >> "$TALK_FILE" 2>/dev/null || true

exit 0
