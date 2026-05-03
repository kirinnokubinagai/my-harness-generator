#!/usr/bin/env bash
# 概要: Claude Code の Stop フックで呼ばれ、Claude の最後の応答を抽出して
#       <project>/dev/docs/talk/<date>.md に自動追記する（マスク済）。
#
# 公式 stdin JSON スキーマ:
#   {
#     "session_id": "...",
#     "transcript_path": "...",   ← この jsonl から最後の assistant message を抽出
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

HARNESS_GENERATOR_DIR="${HARNESS_GENERATOR_DIR:-$HOME/my-harness-generator}"
MASK="$HARNESS_GENERATOR_DIR/scripts/mask-secrets.sh"

# transcript jsonl から最後の assistant message のテキストを抽出
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

DATE_STR=$(date +%Y-%m-%d)
TIME_STR=$(date +%H:%M:%S)
TALK_FILE="$PROJECT_ROOT/dev/docs/talk/${DATE_STR}.md"
mkdir -p "$(dirname "$TALK_FILE")" 2>/dev/null || exit 0
{
  printf '\n## %s - Claude\n\n' "$TIME_STR"
  printf '%s\n' "$MASKED"
} >> "$TALK_FILE" 2>/dev/null || true

exit 0
