#!/usr/bin/env bash
# 概要: Claude Code の Stop フック等で呼ばれ、最後の Claude 応答（と関連ツール出力）を
#       <project>/dev/docs/talk/<date>.md に自動追記する。
#
#       Claude 側でも明示的に talk/ に書く設計だが、書き忘れたケースの保険として
#       transcript.jsonl からこのターンの最後のメッセージを抽出する。
#
# Claude Code の transcript は ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl に保存される。
# stdin で JSON が渡る場合は session_id 等を含むことが多いため、それを利用する。

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=""
if command -v jq >/dev/null 2>&1; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
fi

PROJECT_ROOT="${PWD:-$(pwd)}"
while [ "$PROJECT_ROOT" != "/" ] && [ "$PROJECT_ROOT" != "" ]; do
  [ -f "$PROJECT_ROOT/.my-harness/.config" ] && break
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
[ -f "$PROJECT_ROOT/.my-harness/.config" ] || exit 0

HARNESS_GENERATOR_DIR="${HARNESS_GENERATOR_DIR:-$HOME/my-harness-generator}"
MASK="$HARNESS_GENERATOR_DIR/scripts/mask-secrets.sh"

# transcript ファイルを推定（最新の jsonl）
ENCODED_CWD=$(printf '%s' "$PROJECT_ROOT" | sed 's|/|-|g')
TRANSCRIPT_DIR="$HOME/.claude/projects/$ENCODED_CWD"
if [ -n "$SESSION_ID" ] && [ -f "$TRANSCRIPT_DIR/${SESSION_ID}.jsonl" ]; then
  TRANSCRIPT="$TRANSCRIPT_DIR/${SESSION_ID}.jsonl"
else
  TRANSCRIPT=$(ls -t "$TRANSCRIPT_DIR"/*.jsonl 2>/dev/null | head -1 || true)
fi
[ -f "$TRANSCRIPT" ] || exit 0

# 最後の assistant message を取り出す
if command -v jq >/dev/null 2>&1; then
  LAST_TEXT=$(jq -r 'select(.role=="assistant" or .type=="assistant") | .content // .text // empty' "$TRANSCRIPT" 2>/dev/null \
    | grep -v '^$' | tail -1)
else
  LAST_TEXT=""
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
