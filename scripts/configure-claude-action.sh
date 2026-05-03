#!/usr/bin/env bash
# 概要: bootstrap.env の選択に応じて、Claude Code Action の認証部分を切り替える。
#       Python / yaml に依存せず、sed と awk だけで処理する（macOS / Linux 両対応）。
#       USE_CLAUDE_ACTION=no なら claude-review ジョブを workflow から削除する。
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"
# shellcheck disable=SC1091
source "$ROOT/.my-harness/.config"
cd "$ROOT/dev"

WF=".github/workflows/pr-to-dev.yml"
[ -f "$WF" ] || { echo "[configure-claude-action] $WF が無いのでスキップ"; exit 0; }

if [ "$USE_CLAUDE_ACTION" = "no" ]; then
  # claude-review: ... のブロックを丸ごと削除する。
  # 次の同インデント（2 スペース）のジョブまでを削除対象とする。
  awk '
    BEGIN { skip = 0 }
    /^  claude-review:/ { skip = 1; next }
    skip == 1 && /^  [A-Za-z0-9_-]+:/ { skip = 0 }
    skip == 0 { print }
  ' "$WF" > "$WF.tmp" && mv "$WF.tmp" "$WF"

  # auto-merge.needs から "claude-review" を取り除く
  # `needs: [guard, quality, e2e, claude-review]` の形を想定
  sed -i.bak -E 's/, *claude-review//; s/claude-review *, *//; s/\[claude-review\]/\[\]/' "$WF"
  rm -f "$WF.bak"

  echo "[configure-claude-action] claude-review ジョブを除去しました"
  exit 0
fi

# 認証種別を埋める。pr-to-dev.yml の既定は CLAUDE_CODE_OAUTH_TOKEN なので、
# api を選んだ場合だけ ANTHROPIC_API_KEY に書き換える。
if [ "$CLAUDE_AUTH" = "api" ]; then
  sed -i.bak \
    -e 's|CLAUDE_CODE_OAUTH_TOKEN: \${{ secrets\.CLAUDE_CODE_OAUTH_TOKEN }}|ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}|' \
    "$WF"
  rm -f "$WF.bak"
  echo "[configure-claude-action] 認証=api（ANTHROPIC_API_KEY）を適用"
else
  echo "[configure-claude-action] 認証=oauth（CLAUDE_CODE_OAUTH_TOKEN、既定）を適用"
fi
