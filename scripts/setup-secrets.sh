#!/usr/bin/env bash
# Summary: Interactively sets all required GitHub Secrets / Variables in one pass.
#          Reads bootstrap.env and prompts only for the values needed by the selected features.
# Usage: bash .harness/scripts/setup-secrets.sh <owner/repo>
set -euo pipefail
REPO="${1:?owner/repo required}"

if [ ! -f .my-harness/.config ]; then
  echo "::error:: .my-harness/.config not found. Run bootstrap.sh first."
  exit 1
fi
# shellcheck disable=SC1091
source .my-harness/.config

ask_secret() {
  local name="$1"; local description="$2"
  printf "[secret] %s (%s)\n  Enter value (empty to skip): " "$name" "$description"
  gh secret set "$name" --repo "$REPO" || echo "  → $name skipped"
}
ask_var() {
  local name="$1"; local description="$2"
  printf "[var]    %s (%s)\n  Enter value (empty to skip): " "$name" "$description"
  gh variable set "$name" --repo "$REPO" || echo "  → $name skipped"
}

echo "=================================="
echo " GitHub Secrets / Variables Interactive Setup"
echo "=================================="

# Common
ask_var "DEV_URL"   "Base URL of the dev environment"
ask_var "STAGE_URL" "Base URL of the stage environment (OWASP ZAP target)"
ask_var "PROD_URL"  "Production URL"

# Claude Code Action
if [ "$USE_CLAUDE_ACTION" = "yes" ]; then
  if [ "$CLAUDE_AUTH" = "oauth" ]; then
    ask_secret "CLAUDE_CODE_OAUTH_TOKEN" "OAuth token for Claude Pro/Max subscription"
  else
    ask_secret "ANTHROPIC_API_KEY" "Anthropic API key"
  fi
fi

# Email
if [ "$USE_EMAIL" = "yes" ]; then
  ask_secret "RESEND_API_KEY"      "Resend API key"
  ask_secret "EMAIL_FROM_ADDRESS"  "Sender email address (under an authenticated domain)"
fi

# DB (D1)
if [ "$DB_KIND" = "d1" ]; then
  ask_secret "CLOUDFLARE_API_TOKEN"     "Cloudflare API token (D1 / R2 / Pages permissions)"
  ask_secret "CLOUDFLARE_ACCOUNT_ID"    "Cloudflare account ID"
  ask_secret "CLOUDFLARE_D1_DATABASE_ID" "Production D1 database ID"
  ask_var    "R2_BACKUP_BUCKET"         "R2 bucket name for DB backups"
  ask_secret "R2_ACCESS_KEY_ID"         "R2 access key"
  ask_secret "R2_SECRET_ACCESS_KEY"     "R2 secret"
  ask_secret "R2_ENDPOINT_URL"          "R2 endpoint URL"
  ask_var    "AGE_RECIPIENTS"           "age public keys for backup encryption (space-separated)"
  ask_secret "AGE_SECRET_KEY_STAGE"     "age private key for stage restore"
fi

# Mobile / MobSF
if [ "$USE_IOS" = "yes" ] || [ "$USE_ANDROID" = "yes" ]; then
  ask_secret "MOBSF_API_KEY" "MobSF API key"
fi

# iOS / TestFlight
if [ "$USE_IOS" = "yes" ]; then
  ask_secret "APP_STORE_CONNECT_API_KEY_ID"        "App Store Connect API Key ID"
  ask_secret "APP_STORE_CONNECT_API_ISSUER_ID"     "App Store Connect Issuer ID"
  ask_secret "APP_STORE_CONNECT_API_KEY_BASE64"    "App Store Connect private key (base64)"
  ask_secret "MATCH_PASSWORD"                      "fastlane match encryption password"
  ask_secret "MATCH_GIT_BASIC_AUTHORIZATION"       "Git Basic Auth for match (base64 user:token)"
fi

echo
echo "[setup-secrets] Done. Verify with: gh secret list / gh variable list"
