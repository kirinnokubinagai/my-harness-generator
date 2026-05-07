#!/usr/bin/env bash
# Summary: Detects sensitive values in text and replaces them with <MASKED:type> placeholders.
#          Always pipe through this before writing to docs/talk or docs/spec in /my-harness-init.
#
# Usage:
#   echo "API key: sk-ant-abcd123" | mask-secrets.sh
#   mask-secrets.sh < input.txt > output.txt
#   mask-secrets.sh input.txt > output.txt
#
# Detection targets:
#   - API keys: sk-..., sk-ant-..., sk-proj-..., ghp_..., gho_..., ghu_..., xoxb-..., xoxp-...
#   - AWS access keys: AKIA...
#   - GCP service account JSON
#   - Cloudflare API tokens
#   - JWT three-segment strings
#   - URL credentials: https://user:pass@host
#   - Email addresses
#   - Phone numbers (Japan: 0\d{9,10})
#   - Credit card numbers: 4 groups of 4 digits
#   - PEM private key blocks

set -euo pipefail
INPUT="${1:-/dev/stdin}"

perl -0777 -pe '
  # PEM private key blocks (multi-line match)
  s/-----BEGIN [A-Z ]*PRIVATE KEY[A-Z ]*-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY[A-Z ]*-----/<MASKED:private-key>/g;
' "$INPUT" | perl -pe '
  # GCP service account JSON characteristic line
  s/"type"\s*:\s*"service_account"/<MASKED:gcp-sa>/g;

  # Anthropic / OpenAI / GitHub / Slack / Stripe API keys
  s/sk-ant-[A-Za-z0-9_\-]{20,}/<MASKED:api-key>/g;
  s/sk-(proj-)?[A-Za-z0-9_\-]{20,}/<MASKED:api-key>/g;
  s/gh[pousr]_[A-Za-z0-9]{30,}/<MASKED:api-key>/g;
  s/xox[bpars]-[A-Za-z0-9-]{10,}/<MASKED:api-key>/g;
  s/sk_live_[0-9a-zA-Z]{20,}/<MASKED:api-key>/g;
  s/rk_live_[0-9a-zA-Z]{20,}/<MASKED:api-key>/g;

  # AWS
  s/AKIA[0-9A-Z]{16}/<MASKED:aws-key>/g;

  # JWT three-segment strings
  s/eyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+/<MASKED:jwt>/g;

  # URL credentials (@ must be escaped in perl to avoid array interpolation)
  s|https?://[A-Za-z0-9._%+\-]+:[A-Za-z0-9._%+\-]+\@|<MASKED:url-cred>\@|g;

  # Credit card numbers (loose, digit check)
  s/\b\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b/<MASKED:cc>/g;

  # Phone numbers (Japan)
  s/\b0\d{9,10}\b/<MASKED:phone>/g;

  # Email addresses (exclusion patterns for comments / @example.test etc. are managed by caller)
  s/[A-Za-z0-9._%+\-]+\@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/<MASKED:email>/g;

  # KEY=value pattern: mask the value for known secret key names (API_KEY=xxx, JWT_SECRET=xxx, etc.)
  s/((?i)(API_KEY|API_TOKEN|JWT_SECRET|SESSION_SECRET|ENCRYPTION_KEY|WEBHOOK_SECRET|DATABASE_URL|REDIS_URL|SMTP_PASSWORD|CLOUDFLARE_API_TOKEN|RESEND_API_KEY|ANTHROPIC_API_KEY|OPENAI_API_KEY|STRIPE_API_KEY|STRIPE_SECRET|GITHUB_TOKEN|SUPABASE_SERVICE_ROLE_KEY)\s*[:=]\s*["\x27]?)([^"\x27\s,;]{4,})(["\x27]?)/$1<MASKED:secret>$4/g;
'
