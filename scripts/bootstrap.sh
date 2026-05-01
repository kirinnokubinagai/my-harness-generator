#!/usr/bin/env bash
# 概要: ハーネスのワンコマンド対話セットアップ。
#       使い方: bash <harness>/scripts/bootstrap.sh [<project-root>]
#       これ 1 つだけ叩けば、bare git → worktree → 必要テンプレ配布 → 初期コミットまで終わる。
#       プラットフォーム / DB / メールは対話で選ぶ。汎用化のため固定構成は持たない。

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:-$PWD}"
mkdir -p "$ROOT"
cd "$ROOT"

ask() {
  local prompt="$1"; local default="$2"; local answer
  printf "%s [%s]: " "$prompt" "$default" >&2
  read -r answer || answer=""
  echo "${answer:-$default}"
}

ask_yn() {
  local prompt="$1"; local default="$2"; local a
  a=$(ask "$prompt (y/n)" "$default")
  case "$a" in y|Y|yes|YES) echo "yes" ;; *) echo "no" ;; esac
}

echo "=================================="
echo " 汎用ハーネス ワンコマンドセットアップ"
echo "=================================="
echo "  作業ディレクトリ: $ROOT"
echo

# 1) プロジェクト名
PROJECT_NAME=$(ask "プロジェクト名" "$(basename "$ROOT")")

# 2) プラットフォーム
echo
echo "プラットフォームを選択（複数可、必要なものを y）"
USE_WEB=$(ask_yn "  Web (Hono + React Email)" "y")
USE_IOS=$(ask_yn "  iOS (Swift / SwiftUI)" "n")
USE_ANDROID=$(ask_yn "  Android (Kotlin / Jetpack Compose)" "n")

if [ "$USE_WEB" = "no" ] && [ "$USE_IOS" = "no" ] && [ "$USE_ANDROID" = "no" ]; then
  echo "::error:: 1 つ以上のプラットフォームを選択してください"
  exit 1
fi

# 3) データベース
echo
echo "データベース"
USE_DB=$(ask_yn "  DB を使う" "y")
DB_KIND="none"
if [ "$USE_DB" = "yes" ]; then
  echo "  選択: 1) Cloudflare D1 (推奨)  2) なし"
  DB_KIND=$(ask "  どれを使う？ (d1/none)" "d1")
fi

# 4) メール
echo
USE_EMAIL=$(ask_yn "メール機能（Resend、パスワードリセット含む）を使う" "n")

# 5) E2E
echo
USE_PLAYWRIGHT="no"; USE_MAESTRO="no"
[ "$USE_WEB" = "yes" ] && USE_PLAYWRIGHT=$(ask_yn "E2E に Playwright を使う" "y")
if [ "$USE_IOS" = "yes" ] || [ "$USE_ANDROID" = "yes" ]; then
  USE_MAESTRO=$(ask_yn "E2E に Maestro を使う" "y")
fi

# 6) Claude Code Action
echo
USE_CLAUDE_ACTION=$(ask_yn "PR レビューに Claude Code Action を使う" "y")
CLAUDE_AUTH="api"
if [ "$USE_CLAUDE_ACTION" = "yes" ]; then
  echo "  認証方式: 1) API Key  2) サブスクリプション (Claude Pro/Max OAuth)"
  CLAUDE_AUTH=$(ask "  どっち？ (api/oauth)" "oauth")
fi

# 設定をファイルに保存（後続のスクリプトが参照）
mkdir -p .harness
cat > .harness/.bootstrap.env <<EOF
PROJECT_NAME=$PROJECT_NAME
USE_WEB=$USE_WEB
USE_IOS=$USE_IOS
USE_ANDROID=$USE_ANDROID
USE_DB=$USE_DB
DB_KIND=$DB_KIND
USE_EMAIL=$USE_EMAIL
USE_PLAYWRIGHT=$USE_PLAYWRIGHT
USE_MAESTRO=$USE_MAESTRO
USE_CLAUDE_ACTION=$USE_CLAUDE_ACTION
CLAUDE_AUTH=$CLAUDE_AUTH
EOF

echo
echo "=== 設定確定 ==="
cat .harness/.bootstrap.env
echo

# 1. bare git + worktree
if [ ! -d .bare ]; then
  echo "[bootstrap] bare repository を初期化"
  git init --bare .bare
  printf 'gitdir: ./.bare\n' > .git
  git --git-dir=.bare symbolic-ref HEAD refs/heads/main
  git read-tree --empty
  EMPTY=$(git write-tree)
  C=$(git commit-tree "$EMPTY" -m "chore: initial commit")
  git update-ref refs/heads/main "$C"
  git branch stage main
  git branch dev main
  git worktree add main main
  git worktree add stage stage
  git worktree add dev dev
fi
mkdir -p lanes

# 2. テンプレ配布（プラットフォーム / DB / メールに応じて）
echo "[bootstrap] テンプレートを配布"
bash "$HARNESS_DIR/scripts/setup-platforms.sh" "$ROOT"

# 3. 共通ファイル配布
bash "$HARNESS_DIR/scripts/setup-common.sh" "$ROOT"

# 4. .harness 自体を dev/.harness にコピー（プロジェクト内で実行可能に）
mkdir -p dev/.harness
rsync -a --exclude='.git' --exclude='.bootstrap.env' "$HARNESS_DIR/" dev/.harness/
cp .harness/.bootstrap.env dev/.harness/.bootstrap.env

cat <<EOS

==================================
 ハーネス構築完了
==================================
構成: web=$USE_WEB ios=$USE_IOS android=$USE_ANDROID db=$DB_KIND email=$USE_EMAIL

次のステップ:

  cd $ROOT/dev
  direnv allow              # Nix shell へ自動切替
  pnpm install              # 依存関係
  pnpm exec husky           # husky 9.x セットアップ
  git remote add origin git@github.com:<owner>/<repo>.git
  git push --all origin     # main / stage / dev を一斉 push
  bash .harness/scripts/setup-branch-protection.sh <owner>/<repo>
  bash .harness/scripts/setup-secrets.sh <owner>/<repo>   # 対話で secrets 設定

完成後:
  bash .harness/scripts/new-feature.sh <issue-number> <slug>

EOS
