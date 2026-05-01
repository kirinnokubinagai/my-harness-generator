#!/usr/bin/env bash
# 概要: bootstrap.env の選択に応じて web / ios / android / db / email のテンプレを配布する。
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"
cd "$ROOT"

# shellcheck disable=SC1091
source .harness/.bootstrap.env

# Web
if [ "$USE_WEB" = "yes" ]; then
  echo "[platforms] Web を配布"
  rsync -a --ignore-existing "$HARNESS_DIR/templates/web/" dev/
  if [ "$USE_PLAYWRIGHT" = "yes" ]; then
    rsync -a --ignore-existing "$HARNESS_DIR/templates/playwright/" dev/
  fi
fi

# iOS
if [ "$USE_IOS" = "yes" ]; then
  echo "[platforms] iOS を配布"
  rsync -a --ignore-existing "$HARNESS_DIR/templates/ios/" dev/ios/
fi

# Android
if [ "$USE_ANDROID" = "yes" ]; then
  echo "[platforms] Android (Kotlin) を配布"
  rsync -a --ignore-existing "$HARNESS_DIR/templates/android/" dev/android/
fi

# Maestro（モバイル E2E が選ばれている場合のみ）
if [ "$USE_MAESTRO" = "yes" ]; then
  rsync -a --ignore-existing "$HARNESS_DIR/templates/maestro/" dev/
fi

# DB（D1 のみ対応）
if [ "$DB_KIND" = "d1" ]; then
  echo "[platforms] Cloudflare D1 + Drizzle を配布"
  rsync -a --ignore-existing "$HARNESS_DIR/templates/db/d1/" dev/
fi

# Email（Resend のみ対応）
if [ "$USE_EMAIL" = "yes" ]; then
  echo "[platforms] Resend メール機能を配布"
  rsync -a --ignore-existing "$HARNESS_DIR/templates/email/resend/" dev/
fi

# package.json をオプションに応じて生成
bash "$HARNESS_DIR/scripts/generate-package-json.sh" "$ROOT"

# Claude Code Action 認証分岐の workflow を配置
bash "$HARNESS_DIR/scripts/configure-claude-action.sh" "$ROOT"

echo "[platforms] 完了"
