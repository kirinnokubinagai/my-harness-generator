#!/usr/bin/env bash
# 概要: 本番バックアップを stage に復元した直後、stage で進行中だった追加マイグレーションを再適用する。
#       D1 の場合は `wrangler d1 migrations apply` を stage 環境向けに実行する。
# 使い方: bash .harness/scripts/migrate-after-restore.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck disable=SC1091
[ -f .my-harness/.config ] && source .my-harness/.config || true

if [ "${DB_KIND:-none}" = "d1" ]; then
  echo "[migrate-after-restore] D1 stage に追加マイグレーションを再適用"
  # stage 環境向けのマイグレーション適用。
  # 復元直後はテーブルが本番と同じ状態なので、stage で進行中のスキーマ変更がある場合に必要。
  nix develop --command pnpm exec wrangler d1 migrations apply DB --env staging --remote
else
  echo "[migrate-after-restore] DB は使用していません。スキップ"
fi
