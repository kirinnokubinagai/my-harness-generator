#!/usr/bin/env bash
# 概要: Claude Code の UserPromptSubmit フックで呼ばれ、ユーザー入力を
#       <project>/dev/docs/talk/<date>.md に自動追記する。
#       ファイル書き出し前に mask-secrets.sh で機密値を必ずマスクする。
#
# 想定登録先（settings.json）:
#   {
#     "hooks": {
#       "UserPromptSubmit": [
#         { "command": "bash <harness>/templates/hooks/log-user-prompt.sh" }
#       ]
#     }
#   }
#
# 動作要件:
#   - cwd またはその親に .my-harness/.config が存在するときのみ動作
#     （ハーネスプロジェクト外では何もせず exit 0）
#   - mask-secrets.sh を経由して docs/talk/<date>.md に追記
#
# 注意: フックは全 Claude セッションで毎ターン走るため、軽量に保つ。

set -uo pipefail

# Claude Code はフックに JSON を stdin で渡すので、user_prompt 等を抽出する。
# JSON でない場合（旧仕様や手動テスト）は raw text として扱う。
INPUT=$(cat 2>/dev/null || true)
USER_PROMPT=""
if command -v jq >/dev/null 2>&1; then
  USER_PROMPT=$(printf '%s' "$INPUT" | jq -r '.user_prompt // .prompt // empty' 2>/dev/null || true)
fi
[ -z "$USER_PROMPT" ] && USER_PROMPT="$INPUT"
[ -z "$USER_PROMPT" ] && exit 0

# プロジェクトルート探索（.my-harness/.config の存在）
PROJECT_ROOT="${PWD:-$(pwd)}"
while [ "$PROJECT_ROOT" != "/" ] && [ "$PROJECT_ROOT" != "" ]; do
  if [ -f "$PROJECT_ROOT/.my-harness/.config" ]; then
    break
  fi
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
[ -f "$PROJECT_ROOT/.my-harness/.config" ] || exit 0

# ハーネス本体の位置（mask-secrets.sh を呼ぶため）
HARNESS_GENERATOR_DIR="${HARNESS_GENERATOR_DIR:-$HOME/my-harness-generator}"
MASK="$HARNESS_GENERATOR_DIR/scripts/mask-secrets.sh"

# マスク（mask-secrets.sh があれば通す、無ければ素のまま）
if [ -x "$MASK" ]; then
  MASKED=$(printf '%s' "$USER_PROMPT" | bash "$MASK" 2>/dev/null || printf '%s' "$USER_PROMPT")
else
  MASKED="$USER_PROMPT"
fi

# 追記先（dev/docs/talk/<日付>.md）
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
