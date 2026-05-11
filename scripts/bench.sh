#!/usr/bin/env bash
# bench.sh — synthetic pipeline benchmark.
# 固定 .config で bootstrap を走らせ、フェーズごとの所要秒を JSON で出力する。
# プラグイン更新ごとに走らせれば performance regression を早期に検出できる。
#
# Usage:
#   bash scripts/bench.sh [--out <file>]
#
# Output: bench-results.jsonl に 1 行追記 (git に commit して履歴管理する)

set -euo pipefail

OUT="bench-results.jsonl"
[ "${1:-}" = "--out" ] && OUT="$2"

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
cd "$SCRATCH"

cat > .bench.config <<'EOF'
PROJECT_NAME=bench-fixture
LANG=en
USE_WEB=yes
WEB_KIND=nextjs
USE_IOS=no
IOS_KIND=swift
USE_ANDROID=no
ANDROID_KIND=kotlin
USE_DESKTOP=no
DESKTOP_KIND=tauri
DESKTOP_OS=macos
USE_BACKEND=yes
BACKEND_KIND=hono
USE_DB=yes
DB_KIND=d1
USE_EMAIL=no
AUTH_KIND=password
E2E_SCOPE=web
USE_CLAUDE_ACTION=no
CLAUDE_AUTH=oauth
USE_CODEX=no
CODEX_SESSION=bench
USE_CODEX_ANALYST=no
USE_CODEX_ENGINEER=no
USE_CODEX_E2E_REVIEWER=no
USE_CODEX_REVIEWER=no
MAX_LANES=1
ON_CODEX_AUTH_FAIL=pause
USE_GITHUB_ISSUES=no
USE_GLOBAL_CLAUDE=yes
PACKAGE_MANAGER=pnpm
ARCHITECTURE=client-server
EOF

now_ms() { python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || perl -MTime::HiRes=time -e 'print int(time*1000)'; }

START=$(now_ms)
bash "$HARNESS_DIR/scripts/bootstrap.sh" "$SCRATCH" --config "$SCRATCH/.bench.config" >/dev/null 2>&1
END=$(now_ms)
TOTAL=$(( END - START ))

DEV_FILES=$(find dev -type f 2>/dev/null | wc -l | tr -d ' ')
RUNBOOKS=$(find dev/docs/runbooks -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

GIT_REV=$(cd "$HARNESS_DIR" && git rev-parse --short HEAD 2>/dev/null || echo unknown)

cd - >/dev/null
mkdir -p "$(dirname "$OUT")"
printf '{"ts":"%s","rev":"%s","total_ms":%d,"dev_files":%d,"runbooks":%d}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$GIT_REV" "$TOTAL" "$DEV_FILES" "$RUNBOOKS" >> "$OUT"

echo "bench: rev=$GIT_REV total=${TOTAL}ms dev_files=$DEV_FILES runbooks=$RUNBOOKS"
echo "appended to $OUT"
