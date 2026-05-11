#!/usr/bin/env bash
# upgrade-4-to-5.sh — migrate an adopted 4.x project to the 5.x layout.
#
# 4.x →  5.x の breaking changes:
#   - templates/backend/hono/* が templates/web/src/{interfaces,infrastructure}/ に移管
#   - main.ts が Node `serve()` から Workers `export default { fetch }` に変更
#   - wrangler.toml → wrangler.jsonc (KV/R2 バインディングを追加)
#   - @hono/node-server を package.json から削除
#   - audit_log テーブルが必須
#
# このスクリプトは plugin の最新版を /my-harness-adopt 経由で取り込んだ後に
# 1 度だけ実行する。冪等。
#
# Usage:
#   bash scripts/upgrade-4-to-5.sh <project-root>
#
# Exit codes:
#   0  成功 (no-op を含む)
#   1  競合検出 (手動解決が必要)

set -euo pipefail

ROOT="${1:-$PWD}"
cd "$ROOT" || { echo "::error:: $ROOT not found" >&2; exit 1; }

if [ ! -d .bare ]; then
  echo "::error:: .bare/ not found at $ROOT — run /my-harness-adopt first" >&2
  exit 1
fi

# 1. dev/src/app.ts が旧形 (createApp() 引数なし) なら警告
if [ -f dev/src/app.ts ] && ! grep -q 'createApp(env' dev/src/app.ts; then
  echo "::warning:: dev/src/app.ts は 4.x 形式 (引数なし createApp)。5.x は createApp(env) に変更。"
  echo "  → dev/src/interfaces/http/app.ts に置き換えるか、手動でリファクタしてください"
fi

# 2. dev/src/main.ts が Node serve() なら警告
if [ -f dev/src/main.ts ] && grep -q "@hono/node-server" dev/src/main.ts; then
  echo "::warning:: dev/src/main.ts が @hono/node-server を使用 (4.x)。"
  echo "  → 5.x の Workers entrypoint (export default { fetch }) に書き換える必要あり"
  echo "  → .my-harness/scripts/../../templates/web/src/main.ts を参考に"
fi

# 3. wrangler.toml がある場合は wrangler.jsonc に並べて警告
if [ -f dev/wrangler.toml ] && [ ! -f dev/wrangler.jsonc ]; then
  echo "::info:: dev/wrangler.toml を保持しつつ wrangler.jsonc を配布します"
  if [ -f .my-harness/templates/db/d1/wrangler.jsonc ]; then
    cp .my-harness/templates/db/d1/wrangler.jsonc dev/wrangler.jsonc
  fi
  echo "  → 既存の database_id 等を dev/wrangler.jsonc にコピーしてから dev/wrangler.toml を削除してください"
fi

# 4. @hono/node-server を package.json から自動削除 (jq 必須)
if [ -f dev/package.json ] && command -v jq >/dev/null 2>&1; then
  if jq -e '.dependencies."@hono/node-server"' dev/package.json >/dev/null 2>&1; then
    TMP=$(mktemp)
    jq 'del(.dependencies."@hono/node-server")' dev/package.json > "$TMP"
    mv "$TMP" dev/package.json
    echo "[upgrade] dev/package.json から @hono/node-server を削除"
  fi
fi

# 5. audit_log テーブルの存在確認 — 無ければマイグレーションを案内
if [ -f dev/src/db/schema.ts ] && ! grep -q 'audit_log\|auditLog' dev/src/db/schema.ts; then
  echo "::warning:: dev/src/db/schema.ts に audit_log がありません (5.x で必須)"
  echo "  → cp .my-harness/templates/db/d1/drizzle/0001_production_tables.sql dev/drizzle/"
  echo "  → pnpm db:migrate:remote で適用"
fi

# 6. dev/secrets/ が無ければ作成
if [ ! -d dev/secrets ]; then
  mkdir -p dev/secrets
  cat > dev/secrets/.gitkeep <<'EOF'
# SOPS-encrypted secrets ファイルをここに置きます。
# 詳細は .sops.yaml と docs/SETUP.md を参照。
EOF
  echo "[upgrade] dev/secrets/ を作成"
fi

# 7. runbook 6 本が無ければ配布
mkdir -p dev/docs/runbooks
for f in incident-response.md deploy.md rollback.md dr-plan.md oncall.md postmortem.md; do
  if [ ! -f "dev/docs/runbooks/$f" ] && [ -f ".my-harness/templates/docs/runbooks/$f" ]; then
    cp ".my-harness/templates/docs/runbooks/$f" "dev/docs/runbooks/$f"
    echo "[upgrade] dev/docs/runbooks/$f を配布"
  fi
done

echo
echo "[upgrade] 自動マージできる部分は完了。残り作業:"
echo "  1. dev/src/main.ts を Workers entrypoint へ書き換え"
echo "  2. dev/src/app.ts を dev/src/interfaces/http/app.ts へ移動 + createApp(env) 形へ"
echo "  3. dev/wrangler.jsonc に既存 D1 ID を貼り直し、wrangler.toml を削除"
echo "  4. 必要なら drizzle/0001_production_tables.sql のうち audit_log のみ apply"
echo "  5. pnpm install (新規 deps: @sentry/cloudflare, alchemy, effect)"
echo "  6. bash scripts/doctor.sh で診断"
