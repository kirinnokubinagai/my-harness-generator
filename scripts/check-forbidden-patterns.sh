#!/usr/bin/env bash
# 概要: gitleaks では拾いきれないハードコード禁止パターンを検出する独自スキャン。
#       環境変数として扱うべき値の直書きをコミット段階で弾く。
#       検出ロジックは perl 正規表現で行うため、macOS / Linux の双方で動く。
# 引数: 検査対象のファイルパス（複数可）
# 終了コード: 0 = 問題なし、1 = 違反検出（コミット拒否）

set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "[forbidden-patterns] 引数にファイルが指定されていません。スキップします。"
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

# 環境変数として扱うべきキーの一覧
SENSITIVE_KEYS='JWT_SECRET|JWT_REFRESH_SECRET|DATABASE_URL|API_KEY|API_TOKEN|STRIPE_KEY|STRIPE_SECRET|STRIPE_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|CLOUDFLARE_API_TOKEN|CLOUDFLARE_ACCOUNT_ID|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|GCP_SERVICE_ACCOUNT|GITHUB_TOKEN|SUPABASE_SERVICE_ROLE_KEY|SUPABASE_ANON_KEY|SENTRY_DSN|REDIS_URL|SMTP_PASSWORD|SMTP_USER|SESSION_SECRET|ENCRYPTION_KEY|WEBHOOK_SECRET'

# 1) コードの中で「KEY = "literal"」の形で書かれている直書きを検出
# 許容: process.env.KEY、import.meta.env.KEY、Deno.env.get("KEY")、空文字、テンプレ変数（${...}）
RE_HARDCODE='(?i)\b('"$SENSITIVE_KEYS"')\s*[:=]\s*["\x27](?!\s*["\x27])(?![^"\x27]*\$\{)[^"\x27]{4,}["\x27]'

# 2) URL に資格情報が埋まっているケース
RE_URL_CRED='(?i)https?://[A-Za-z0-9._~%-]+:[A-Za-z0-9._~%-]+@[A-Za-z0-9.-]+'

# 3) localhost 以外への DB 接続文字列ハードコード
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
    VIOLATIONS+=("$f: 環境変数として扱うべき値が直書きされています")
    echo "$hits" | sed 's/^/    /'
  fi

  hits=$(run_perl "$RE_URL_CRED" "$f")
  if [ -n "$hits" ]; then
    VIOLATIONS+=("$f: URL に資格情報が埋まっています")
    echo "$hits" | sed 's/^/    /'
  fi

  hits=$(run_perl "$RE_DB_DSN" "$f")
  if [ -n "$hits" ]; then
    VIOLATIONS+=("$f: 本番想定ホストへの接続文字列が直書きされています")
    echo "$hits" | sed 's/^/    /'
  fi

  # 4) 平文 .env のコミットは禁止
  base=$(basename "$f")
  case "$base" in
    .env|.env.local|.env.production|.env.staging|.env.development)
      VIOLATIONS+=("$f: 平文 .env のコミットは禁止です（.env.example のみ許可）")
      ;;
  esac
done

if [ "${#VIOLATIONS[@]}" -gt 0 ]; then
  echo "" >&2
  echo "[forbidden-patterns] 違反を検出しました:" >&2
  for v in "${VIOLATIONS[@]}"; do echo "  - $v" >&2; done
  echo "" >&2
  echo "対処方法:" >&2
  echo "  1) 値を環境変数化し、process.env.XXX 経由で参照してください" >&2
  echo "  2) 共有が必要な値は SOPS+age で暗号化してください（.harness/templates/security/sops.yaml 参照）" >&2
  echo "  3) サンプルは .env.example、テスト用は __fixtures__ または *.example に配置してください" >&2
  exit 1
fi

echo "[forbidden-patterns] OK"
exit 0
