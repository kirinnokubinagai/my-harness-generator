#!/usr/bin/env bash
# 概要: Claude Code の UserPromptSubmit フックで呼ばれ、ユーザー入力を
#       <project>/dev/docs/talk/<date>.md に自動追記する。
#       ファイル書き出し前に mask-secrets.sh で機密値を必ずマスクする。
#
# 公式 stdin JSON スキーマ（Claude Code Hooks reference より）:
#   {
#     "session_id": "...",
#     "transcript_path": "...",
#     "cwd": "...",
#     "permission_mode": "...",
#     "hook_event_name": "UserPromptSubmit",
#     "prompt": "ユーザー入力本文"
#   }
#
# 想定登録先（settings.json）:
#   {
#     "hooks": {
#       "UserPromptSubmit": [
#         { "command": "bash <harness>/templates/hooks/log-user-prompt.sh" }
#       ]
#     }
#   }

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

# JSON から prompt と cwd を抽出（jq があれば使う）
USER_PROMPT=""
WORK_DIR=""
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  USER_PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
  WORK_DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
fi
[ -z "$USER_PROMPT" ] && USER_PROMPT="$INPUT"
[ -z "$USER_PROMPT" ] && exit 0
[ -z "$WORK_DIR" ] && WORK_DIR="${PWD:-$(pwd)}"

# プロジェクトルート探索（.my-harness/.config の存在）
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

TALK_DIR="$PROJECT_ROOT/dev/docs/talk"
mkdir -p "$TALK_DIR" 2>/dev/null || exit 0

DATE_STR=$(date +%Y-%m-%d)
TIME_STR=$(date +%H:%M:%S)
TALK_FILE="$TALK_DIR/${DATE_STR}.md"

{
  printf '\n## %s - User\n\n' "$TIME_STR"
  printf '%s\n' "$MASKED"
} >> "$TALK_FILE" 2>/dev/null || true

exit 0
