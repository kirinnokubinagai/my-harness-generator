#!/usr/bin/env bash
# score.sh — Production Readiness Score for a harness-generated project.
# Evaluates the checklist in rules/production.md and prints a 0-100 score.
#
# Usage:
#   bash scripts/score.sh             # human-readable
#   bash scripts/score.sh --json      # machine-readable
#
# Exit codes:
#   0  score ≥ 80
#   1  score 60-79
#   2  score < 60

set -u

JSON=0
[ "${1:-}" = "--json" ] && JSON=1

__resolve_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}
ROOT="$(__resolve_root "$PWD")"
DEV="$ROOT/dev"

ITEMS=()
SCORES=()
MAX=()
NOTES=()

check() {
  local item="$1" max="$2" condition="$3" pass_msg="$4" fail_msg="$5"
  ITEMS+=("$item")
  MAX+=("$max")
  if eval "$condition" >/dev/null 2>&1; then
    SCORES+=("$max")
    NOTES+=("✓ $pass_msg")
  else
    SCORES+=(0)
    NOTES+=("✗ $fail_msg")
  fi
}

# --- 結果ファイル群の存在 ---
check "runbooks-complete" 10 \
  "[ -f $DEV/docs/runbooks/incident-response.md ] && [ -f $DEV/docs/runbooks/deploy.md ] && [ -f $DEV/docs/runbooks/rollback.md ] && [ -f $DEV/docs/runbooks/dr-plan.md ] && [ -f $DEV/docs/runbooks/oncall.md ] && [ -f $DEV/docs/runbooks/postmortem.md ]" \
  "6 runbook 揃い" \
  "不足ある runbook を埋めること"

check "wrangler-jsonc" 5 \
  "[ -f $DEV/wrangler.jsonc ] && ! grep -q 'REPLACE_WITH' $DEV/wrangler.jsonc" \
  "wrangler.jsonc に実 ID が入っている" \
  "wrangler.jsonc に REPLACE_WITH プレースホルダ残存"

check "alchemy-stack" 5 \
  "[ -f $DEV/alchemy.run.ts ]" \
  "Alchemy v2 スタック宣言あり" \
  "alchemy.run.ts なし"

check "audit-log-schema" 5 \
  "grep -q 'audit_log\\|auditLog' $DEV/src/db/schema.ts" \
  "audit_log スキーマあり" \
  "audit_log スキーマ未定義"

check "renovate-config" 5 \
  "[ -f $DEV/renovate.json ]" \
  "Renovate 設定あり" \
  "Renovate 未設定"

check "dependabot-config" 3 \
  "[ -f $DEV/.github/dependabot.yml ]" \
  "Dependabot 設定あり" \
  "Dependabot 未設定"

check "ci-codeql" 5 \
  "[ -f $DEV/.github/workflows/codeql.yml ]" \
  "CodeQL workflow あり" \
  "CodeQL 未設定"

check "ci-sbom" 5 \
  "[ -f $DEV/.github/workflows/sbom.yml ]" \
  "SBOM workflow あり" \
  "SBOM 未設定"

check "ci-license" 3 \
  "[ -f $DEV/.github/workflows/license-check.yml ]" \
  "ライセンス監査 workflow あり" \
  "ライセンス監査 未設定"

check "ci-k6" 3 \
  "[ -f $DEV/.github/workflows/k6-smoke.yml ] && [ -f $DEV/tests/load/smoke.js ]" \
  "k6 smoke 完備" \
  "k6 smoke 未配備"

check "ci-lighthouse" 3 \
  "[ -f $DEV/.github/workflows/lighthouse.yml ] && [ -f $DEV/lighthouserc.json ]" \
  "Lighthouse CI 完備" \
  "Lighthouse CI 未配備"

check "secrets-sops" 5 \
  "[ -f $DEV/.sops.yaml ] && [ -d $DEV/secrets ]" \
  "SOPS + secrets/ 完備" \
  "SOPS / secrets ディレクトリ未配備"

# --- middleware 配線 ---
check "middleware-rate-limit" 5 \
  "[ -f $DEV/src/interfaces/http/middleware/rate-limit.ts ]" \
  "rate-limit middleware あり" \
  "rate-limit middleware なし"

check "middleware-idempotency" 5 \
  "[ -f $DEV/src/interfaces/http/middleware/idempotency.ts ]" \
  "idempotency middleware あり" \
  "idempotency middleware なし"

check "middleware-cors" 3 \
  "[ -f $DEV/src/interfaces/http/middleware/cors.ts ]" \
  "strict CORS middleware あり" \
  "strict CORS middleware なし"

check "middleware-logger" 3 \
  "[ -f $DEV/src/interfaces/http/middleware/request-logger.ts ]" \
  "request-logger middleware あり" \
  "request-logger middleware なし"

# --- 認証 ---
check "auth-route" 5 \
  "[ -f $DEV/src/interfaces/http/routes/auth.ts ]" \
  "認証ルート (login / password-reset) あり" \
  "認証ルート未実装"

# --- OpenAPI ---
check "openapi-spec" 5 \
  "grep -q 'OpenAPIHono\\|/openapi.json' $DEV/src/interfaces/http/app.ts" \
  "OpenAPI 仕様配信あり" \
  "OpenAPI 未設定"

# --- tests ---
TEST_COUNT=$(find "$DEV/src" -name '*.test.ts' 2>/dev/null | wc -l | tr -d ' ')
ITEMS+=("tests-count")
MAX+=(10)
if [ "${TEST_COUNT:-0}" -ge 5 ]; then
  SCORES+=(10)
  NOTES+=("✓ ${TEST_COUNT} 件のテストファイル")
elif [ "${TEST_COUNT:-0}" -ge 1 ]; then
  SCORES+=(5)
  NOTES+=("△ ${TEST_COUNT} 件のテストファイル (5 件以上で満点)")
else
  SCORES+=(0)
  NOTES+=("✗ テストファイル 0 件")
fi

# --- 集計 ---
TOTAL=0
MAX_TOTAL=0
n=${#SCORES[@]}
for ((i=0; i<n; i++)); do
  TOTAL=$(( TOTAL + SCORES[i] ))
  MAX_TOTAL=$(( MAX_TOTAL + MAX[i] ))
done
PCT=$(( MAX_TOTAL > 0 ? TOTAL * 100 / MAX_TOTAL : 0 ))

if [ "$JSON" -eq 1 ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo '{"error":"jq required for --json"}' >&2
    exit 64
  fi
  jq_args=()
  for ((i=0; i<n; i++)); do
    jq_args+=(--arg "i$i" "${ITEMS[$i]}" --arg "n$i" "${NOTES[$i]}" --argjson "s$i" "${SCORES[$i]}" --argjson "m$i" "${MAX[$i]}")
  done
  filter='{score:'"$TOTAL"',max:'"$MAX_TOTAL"',percent:'"$PCT"',items:['
  for ((i=0; i<n; i++)); do
    [ $i -gt 0 ] && filter+=','
    filter+='{item:$i'"$i"',score:$s'"$i"',max:$m'"$i"',note:$n'"$i"'}'
  done
  filter+=']}'
  jq -n "${jq_args[@]}" "$filter"
else
  for ((i=0; i<n; i++)); do
    printf '  %-25s  %2d / %2d   %s\n' "${ITEMS[$i]}" "${SCORES[$i]}" "${MAX[$i]}" "${NOTES[$i]}"
  done
  echo
  printf 'Score: %d / %d  (%d%%)\n' "$TOTAL" "$MAX_TOTAL" "$PCT"
fi

if [ "$PCT" -ge 80 ]; then exit 0; fi
if [ "$PCT" -ge 60 ]; then exit 1; fi
exit 2
