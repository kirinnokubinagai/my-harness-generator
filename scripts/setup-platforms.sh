#!/usr/bin/env bash
# Summary: Distributes web / ios / android / db / email templates based on bootstrap.env selections.
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"
cd "$ROOT"

# shellcheck disable=SC1091
source .my-harness/.config

# Web
if [ "$USE_WEB" = "yes" ]; then
  echo "[platforms] Distributing Web templates"
  rsync -a --ignore-existing "$HARNESS_DIR/templates/web/" dev/
  if [ "$USE_PLAYWRIGHT" = "yes" ]; then
    rsync -a --ignore-existing "$HARNESS_DIR/templates/playwright/" dev/
  fi
fi

# iOS
if [ "$USE_IOS" = "yes" ]; then
  echo "[platforms] Distributing iOS templates"
  rsync -a --ignore-existing "$HARNESS_DIR/templates/ios/" dev/ios/
fi

# Android
if [ "$USE_ANDROID" = "yes" ]; then
  echo "[platforms] Distributing Android (Kotlin) templates"
  rsync -a --ignore-existing "$HARNESS_DIR/templates/android/" dev/android/
fi

# Maestro (only when mobile E2E is selected)
if [ "$USE_MAESTRO" = "yes" ]; then
  rsync -a --ignore-existing "$HARNESS_DIR/templates/maestro/" dev/
fi

# DB (D1 only)
if [ "$DB_KIND" = "d1" ]; then
  echo "[platforms] Distributing Cloudflare D1 + Drizzle templates"
  rsync -a --ignore-existing "$HARNESS_DIR/templates/db/d1/" dev/
fi

# Email (Resend only)
if [ "$USE_EMAIL" = "yes" ]; then
  echo "[platforms] Distributing Resend email templates"
  rsync -a --ignore-existing "$HARNESS_DIR/templates/email/resend/" dev/
fi

# Generate package.json based on selected options
bash "$HARNESS_DIR/scripts/generate-package-json.sh" "$ROOT"

# Place the Claude Code Action workflow with the correct auth branch
bash "$HARNESS_DIR/scripts/configure-claude-action.sh" "$ROOT"

echo "[platforms] Done"
