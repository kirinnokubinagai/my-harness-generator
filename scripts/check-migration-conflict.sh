#!/usr/bin/env bash
# 概要: 親 issue 内で複数の子 issue が同時に Drizzle マイグレーションを生成していないかチェックする。
#       同一親配下の feat ブランチで drizzle/ 配下の SQL を 2 つ以上の枝が触っていたら警告して終了する。
# 使い方: bash .harness/scripts/check-migration-conflict.sh <parent-issue-number>
set -euo pipefail
PARENT="${1:?parent issue number required}"
cd "$(git rev-parse --show-toplevel)"

# 親に紐づく子 issue から派生したブランチを GitHub から取得
CHILDREN=$(gh issue view "$PARENT" --json body --jq '.body' | grep -oE '#[0-9]+' | tr -d '#' || true)

OFFENDERS=()
for c in $CHILDREN; do
  BR=$(gh pr list --search "$c" --state open --json headRefName --jq '.[0].headRefName' 2>/dev/null || true)
  [ -z "$BR" ] && continue
  TOUCHED=$(git diff --name-only origin/dev..."origin/$BR" -- drizzle/ 2>/dev/null | wc -l | tr -d ' ')
  if [ "$TOUCHED" != "0" ]; then
    OFFENDERS+=("$BR(#$c) drizzle/ ファイル数=$TOUCHED")
  fi
done

if [ "${#OFFENDERS[@]}" -gt 1 ]; then
  echo "::error:: 親 #$PARENT 配下で複数の子 issue がマイグレーションを生成しています:"
  for o in "${OFFENDERS[@]}"; do echo "  - $o"; done
  echo "対処: マイグレーションは 1 子 issue で集中して書いてください（順序衝突防止）。"
  exit 1
fi

echo "[check-migration-conflict] OK"
