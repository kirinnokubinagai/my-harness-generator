#!/usr/bin/env bash
# Summary: Custom scan to detect hardcoded patterns that gitleaks cannot catch.
#          Blocks values that should be environment variables from being committed.
#          Detection logic uses perl regex, so it works on both macOS and Linux.
# Arguments: File paths to scan (one or more)
# Exit code: 0 = no issues, 1 = violations detected (commit rejected)

set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "[forbidden-patterns] No files specified. Skipping."
  exit 0
fi

VIOLATIONS=()

should_skip() {
  case "$1" in
    *.example|*.lock|*pnpm-lock.yaml|*package-lock.json|*yarn.lock) return 0 ;;
    *.test.*|*.spec.*|*__fixtures__*|*__mocks__*|*/fixtures/*) return 0 ;;
    *.md|*.svg|*.png|*.jpg|*.jpeg|*.gif|*.pdf|*.ico) return 0 ;;
  esac
  return 1
}

# List of keys that must be managed as environment variables
SENSITIVE_KEYS='JWT_SECRET|JWT_REFRESH_SECRET|DATABASE_URL|API_KEY|API_TOKEN|STRIPE_KEY|STRIPE_SECRET|STRIPE_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|CLOUDFLARE_API_TOKEN|CLOUDFLARE_ACCOUNT_ID|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|GCP_SERVICE_ACCOUNT|GITHUB_TOKEN|SUPABASE_SERVICE_ROLE_KEY|SUPABASE_ANON_KEY|SENTRY_DSN|REDIS_URL|SMTP_PASSWORD|SMTP_USER|SESSION_SECRET|ENCRYPTION_KEY|WEBHOOK_SECRET'

# 1) Detect hardcoded literals in the form KEY = "literal" in code
# Allowed: process.env.KEY, import.meta.env.KEY, Deno.env.get("KEY"), empty string, template variables (${...})
RE_HARDCODE='(?i)\b('"$SENSITIVE_KEYS"')\s*[:=]\s*["\x27](?!\s*["\x27])(?![^"\x27]*\$\{)[^"\x27]{4,}["\x27]'

# 2) URL credentials embedded in the URL
RE_URL_CRED='(?i)https?://[A-Za-z0-9._~%-]+:[A-Za-z0-9._~%-]+@[A-Za-z0-9.-]+'

# 3) Production DB connection strings hardcoded (non-localhost hosts)
RE_DB_DSN='(?i)(postgres(ql)?|mysql|mongodb(\+srv)?|redis)://(?!localhost|127\.0\.0\.1|0\.0\.0\.0|host\.docker\.internal)[A-Za-z0-9.\-_:@/%?=&]{8,}'

run_perl() {
  PAT="$1" perl -ne 'print "$.: $_" if m{$ENV{PAT}}' "$2" 2>/dev/null
}

for f in "$@"; do
  [ -f "$f" ] || continue
  should_skip "$f" && continue

  case "$f" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.go|*.rs|*.java|*.kt|\
    *.json|*.yml|*.yaml|*.toml|*.tf|*.sh|*.bash|*.zsh|.env|.env.*) ;;
    *) continue ;;
  esac

  hits=$(run_perl "$RE_HARDCODE" "$f")
  if [ -n "$hits" ]; then
    VIOLATIONS+=("$f: value that should be an environment variable is hardcoded")
    echo "$hits" | sed 's/^/    /'
  fi

  hits=$(run_perl "$RE_URL_CRED" "$f")
  if [ -n "$hits" ]; then
    VIOLATIONS+=("$f: credentials are embedded in the URL")
    echo "$hits" | sed 's/^/    /'
  fi

  hits=$(run_perl "$RE_DB_DSN" "$f")
  if [ -n "$hits" ]; then
    VIOLATIONS+=("$f: connection string targeting a production host is hardcoded")
    echo "$hits" | sed 's/^/    /'
  fi

  # 4) Committing a plain-text .env file is prohibited
  base=$(basename "$f")
  case "$base" in
    .env|.env.local|.env.production|.env.staging|.env.development)
      VIOLATIONS+=("$f: committing a plain-text .env file is prohibited (only .env.example is allowed)")
      ;;
  esac
done

if [ "${#VIOLATIONS[@]}" -gt 0 ]; then
  echo "" >&2
  echo "[forbidden-patterns] Violations detected:" >&2
  for v in "${VIOLATIONS[@]}"; do echo "  - $v" >&2; done
  echo "" >&2
  echo "How to fix:" >&2
  echo "  1) Move the value to an environment variable and reference it via process.env.XXX" >&2
  echo "  2) For shared values, encrypt with SOPS+age (see .harness/templates/security/sops.yaml)" >&2
  echo "  3) Place samples in .env.example and test fixtures in __fixtures__ or *.example" >&2
  exit 1
fi

echo "[forbidden-patterns] OK"
exit 0
