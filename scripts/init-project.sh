#!/usr/bin/env bash
# 概要: 後方互換のためのリダイレクト。実体は bootstrap.sh。
#       新規利用者は bootstrap.sh を直接呼ぶことを推奨する。
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "[init-project] このスクリプトは廃止予定です。bootstrap.sh に転送します。"
exec bash "$HARNESS_DIR/scripts/bootstrap.sh" "$@"
