#!/usr/bin/env bash
# 概要: テキストから機密値を検出して <MASKED:type> プレースホルダに置換する。
#       /my-harness-init で docs/talk / docs/spec に書く前に必ずパイプで通すこと。
#
# 使い方:
#   echo "API key: sk-ant-abcd123" | mask-secrets.sh
#   mask-secrets.sh < input.txt > output.txt
#   mask-secrets.sh input.txt > output.txt
#
# 検出対象:
#   - API キー: sk-..., sk-ant-..., sk-proj-..., ghp_..., gho_..., ghu_..., xoxb-..., xoxp-...
#   - AWS アクセスキー: AKIA...
#   - GCP サービスアカウント JSON
#   - Cloudflare API トークン
#   - JWT 三段ドット
#   - URL 内資格情報: https://user:pass@host
#   - メールアドレス
#   - 電話番号（日本: 0\d{9,10}）
#   - クレジットカード: 4 桁 x4
#   - PEM 形式秘密鍵ブロック

set -euo pipefail
INPUT="${1:-/dev/stdin}"

perl -0777 -pe '
  # PEM 形式秘密鍵（複数行マッチ）
  s/-----BEGIN [A-Z ]*PRIVATE KEY[A-Z ]*-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY[A-Z ]*-----/<MASKED:private-key>/g;
' "$INPUT" | perl -pe '
  # GCP サービスアカウント JSON の特徴行
  s/"type"\s*:\s*"service_account"/<MASKED:gcp-sa>/g;

  # Anthropic / OpenAI / GitHub / Slack / Stripe API キー
  s/sk-ant-[A-Za-z0-9_\-]{20,}/<MASKED:api-key>/g;
  s/sk-(proj-)?[A-Za-z0-9_\-]{20,}/<MASKED:api-key>/g;
  s/gh[pousr]_[A-Za-z0-9]{30,}/<MASKED:api-key>/g;
  s/xox[bpars]-[A-Za-z0-9-]{10,}/<MASKED:api-key>/g;
  s/sk_live_[0-9a-zA-Z]{20,}/<MASKED:api-key>/g;
  s/rk_live_[0-9a-zA-Z]{20,}/<MASKED:api-key>/g;

  # AWS
  s/AKIA[0-9A-Z]{16}/<MASKED:aws-key>/g;

  # JWT 三段ドット
  s/eyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+/<MASKED:jwt>/g;

  # URL 内資格情報（@ は perl で配列補間されるためエスケープ）
  s|https?://[A-Za-z0-9._%+\-]+:[A-Za-z0-9._%+\-]+\@|<MASKED:url-cred>\@|g;

  # クレジットカード番号（緩い、桁検査）
  s/\b\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b/<MASKED:cc>/g;

  # 電話番号（日本）
  s/\b0\d{9,10}\b/<MASKED:phone>/g;

  # メールアドレス（コメント / @example.test 等の固有除外パターンは callerで管理）
  s/[A-Za-z0-9._%+\-]+\@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/<MASKED:email>/g;

  # KEY=value 形式で機密キー名右辺の値（API_KEY=xxx, JWT_SECRET=xxx 等）
  s/((?i)(API_KEY|API_TOKEN|JWT_SECRET|SESSION_SECRET|ENCRYPTION_KEY|WEBHOOK_SECRET|DATABASE_URL|REDIS_URL|SMTP_PASSWORD|CLOUDFLARE_API_TOKEN|RESEND_API_KEY|ANTHROPIC_API_KEY|OPENAI_API_KEY|STRIPE_API_KEY|STRIPE_SECRET|GITHUB_TOKEN|SUPABASE_SERVICE_ROLE_KEY)\s*[:=]\s*["\x27]?)([^"\x27\s,;]{4,})(["\x27]?)/$1<MASKED:secret>$4/g;
'
