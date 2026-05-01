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
CLAUDE_AUTH="oauth"
if [ "$USE_CLAUDE_ACTION" = "yes" ]; then
  echo "  認証方式: api = Anthropic API キー / oauth = サブスクリプション (Claude Pro/Max)"
  while :; do
    CLAUDE_AUTH=$(ask "  どっち？ (api/oauth)" "oauth")
    case "$CLAUDE_AUTH" in
      api|API)   CLAUDE_AUTH=api;   break ;;
      oauth|OAUTH) CLAUDE_AUTH=oauth; break ;;
      *) echo "    → 'api' か 'oauth' で答えてください" ;;
    esac
  done
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

# 1. bare git の作成（無い場合のみ）
if [ ! -d .bare ]; then
  echo "[bootstrap] bare repository を初期化"
  git init --bare .bare
fi

# .git ファイルの存在を保証（直前のセットアップが中断していた場合の救済）
[ -f .git ] || printf 'gitdir: ./.bare\n' > .git

# 2. main ブランチに初期コミットを保証（refs が無ければ作る、冪等）
if ! git --git-dir=.bare rev-parse --verify refs/heads/main >/dev/null 2>&1; then
  echo "[bootstrap] 初期コミットと main ブランチを作成"
  git --git-dir=.bare symbolic-ref HEAD refs/heads/main
  git read-tree --empty
  EMPTY=$(git write-tree)
  INITIAL_COMMIT=$(git commit-tree "$EMPTY" -m "chore: initial commit")
  git update-ref refs/heads/main "$INITIAL_COMMIT"
fi

# 3. stage / dev ブランチを保証（main 起点で生やす、既存ならスキップ）
ensure_branch() {
  local branchName="$1"
  if ! git --git-dir=.bare rev-parse --verify "refs/heads/$branchName" >/dev/null 2>&1; then
    echo "[bootstrap] ブランチ '$branchName' を main から作成"
    git --git-dir=.bare branch "$branchName" main
  fi
}
ensure_branch stage
ensure_branch dev

# 4. worktree の作成（存在しないものだけ作る、冪等）
#    判定は worktree が必ず作る `.git` ファイル（dir でなく file）の存在で行う。
#    git worktree list の出力パスは macOS で /private プレフィックスが付くなど比較が不安定なため避ける。
#    手動 rm されて bare 側に残った登録を掃除するため、最初に prune する。
git worktree prune
ensure_worktree() {
  local name="$1"
  if [ -f "$name/.git" ]; then
    return 0
  fi
  if [ -e "$name" ]; then
    echo "::warning:: '$name' が既に存在しますが worktree マーカが見つかりません。スキップして続行します。"
    return 0
  fi
  echo "[bootstrap] worktree '$name' を作成"
  # 万一 bare 側に名前だけ残っているケースに備えて --force で確実に作る
  git worktree add --force "$name" "$name"
}
ensure_worktree main
ensure_worktree stage
ensure_worktree dev

mkdir -p lanes

# 2. 共通ファイル（Biome / Husky / Nix / GitHub workflows / issue template / tsconfig 等）を先に配布
#    setup-platforms.sh の中で workflow を書き換えるため、先に置いておく必要がある
echo "[bootstrap] 共通ファイルを配布"
bash "$HARNESS_DIR/scripts/setup-common.sh" "$ROOT"

# 3. プラットフォーム / DB / メールに応じたテンプレ配布 + workflow / package.json の動的編集
echo "[bootstrap] プラットフォーム別テンプレを配布"
bash "$HARNESS_DIR/scripts/setup-platforms.sh" "$ROOT"

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
