#!/usr/bin/env bash
# 概要: GitHub の Secrets / Variables を対話的にまとめて設定する。
#       bootstrap.env を読んで、選んだ機能に必要な分だけプロンプトする。
# 使い方: bash .harness/scripts/setup-secrets.sh <owner/repo>
set -euo pipefail
REPO="${1:?owner/repo required}"

if [ ! -f .my-harness/.config ]; then
  echo "::error:: .my-harness/.config が見つかりません。先に bootstrap.sh を実行してください"
  exit 1
fi
# shellcheck disable=SC1091
source .my-harness/.config

ask_secret() {
  local name="$1"; local description="$2"
  printf "[secret] %s (%s)\n  値を入力（空でスキップ）: " "$name" "$description"
  gh secret set "$name" --repo "$REPO" || echo "  → $name はスキップ"
}
ask_var() {
  local name="$1"; local description="$2"
  printf "[var]    %s (%s)\n  値を入力（空でスキップ）: " "$name" "$description"
  gh variable set "$name" --repo "$REPO" || echo "  → $name はスキップ"
}

echo "=================================="
echo " GitHub Secrets / Variables 対話セットアップ"
echo "=================================="

# 共通
ask_var "DEV_URL"   "dev 環境のベース URL"
ask_var "STAGE_URL" "stage 環境のベース URL（OWASP ZAP の対象）"
ask_var "PROD_URL"  "本番 URL"

# Claude Code Action
if [ "$USE_CLAUDE_ACTION" = "yes" ]; then
  if [ "$CLAUDE_AUTH" = "oauth" ]; then
    ask_secret "CLAUDE_CODE_OAUTH_TOKEN" "Claude Pro/Max サブスクリプションの OAuth トークン"
  else
    ask_secret "ANTHROPIC_API_KEY" "Anthropic API キー"
  fi
fi

# メール
if [ "$USE_EMAIL" = "yes" ]; then
  ask_secret "RESEND_API_KEY"      "Resend API キー"
  ask_secret "EMAIL_FROM_ADDRESS"  "送信元メールアドレス（認証済みドメイン配下）"
fi

# DB（D1）
if [ "$DB_KIND" = "d1" ]; then
  ask_secret "CLOUDFLARE_API_TOKEN"     "Cloudflare API トークン（D1 / R2 / Pages 権限）"
  ask_secret "CLOUDFLARE_ACCOUNT_ID"    "Cloudflare アカウント ID"
  ask_secret "CLOUDFLARE_D1_DATABASE_ID" "本番 D1 データベース ID"
  ask_var    "R2_BACKUP_BUCKET"         "DB バックアップ先の R2 バケット名"
  ask_secret "R2_ACCESS_KEY_ID"         "R2 アクセスキー"
  ask_secret "R2_SECRET_ACCESS_KEY"     "R2 シークレット"
  ask_secret "R2_ENDPOINT_URL"          "R2 エンドポイント URL"
  ask_var    "AGE_RECIPIENTS"           "バックアップ暗号化用 age 公開鍵（スペース区切り）"
  ask_secret "AGE_SECRET_KEY_STAGE"     "stage 復元用 age 秘密鍵"
fi

# モバイル / MobSF
if [ "$USE_IOS" = "yes" ] || [ "$USE_ANDROID" = "yes" ]; then
  ask_secret "MOBSF_API_KEY" "MobSF API キー"
fi

# iOS / TestFlight
if [ "$USE_IOS" = "yes" ]; then
  ask_secret "APP_STORE_CONNECT_API_KEY_ID"        "App Store Connect API Key ID"
  ask_secret "APP_STORE_CONNECT_API_ISSUER_ID"     "App Store Connect Issuer ID"
  ask_secret "APP_STORE_CONNECT_API_KEY_BASE64"    "App Store Connect 秘密鍵（base64）"
  ask_secret "MATCH_PASSWORD"                      "fastlane match の暗号化パスワード"
  ask_secret "MATCH_GIT_BASIC_AUTHORIZATION"       "match 用 Git Basic 認証 (base64 user:token)"
fi

echo
echo "[setup-secrets] 完了。設定状況は gh secret list / gh variable list で確認できます。"
