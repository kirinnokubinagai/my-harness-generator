#!/usr/bin/env bash
# 概要: Codex CLI のログイン状態を確認する。
#       Codex CLI 自体に "auth status" コマンドが存在しないため、auth.json の存在と
#       軽い codex exec の成功で多段検証する。
# 終了コード: 0 = ログイン済 / 1 = 未ログイン or 不明 / 127 = codex CLI 未インストール
# 標準出力: 状態 (logged-in / not-logged-in / not-installed)

set -uo pipefail

if ! command -v codex >/dev/null 2>&1; then
  echo "not-installed"
  echo "::error:: codex CLI が見つかりません。インストール: npm i -g @openai/codex" >&2
  exit 127
fi

AUTH_FILE="${HOME}/.codex/auth.json"
if [ ! -f "$AUTH_FILE" ]; then
  echo "not-logged-in"
  echo "::warning:: $AUTH_FILE がありません。'codex login' を実行してください。" >&2
  exit 1
fi

# auth.json の中身を緩く検証（access_token または api_key のいずれかがあれば OK）
# jq があれば厳密に、無ければ grep で代替
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
  echo "::warning:: auth.json にトークンが見つかりません。'codex login' を再実行してください。" >&2
  exit 1
fi

echo "logged-in"
exit 0
