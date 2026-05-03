#!/usr/bin/env bash
# 概要: ハーネスのワンコマンド対話セットアップ。
#
# 使い方:
#   bash bootstrap.sh <project-root>                       # 対話モード（人間向け）
#   bash bootstrap.sh <project-root> --config <file>       # 非対話モード（Claude が /my-harness-init から呼ぶ）
#
# 設定ファイル形式（.my-harness/.config 互換）:
#   PROJECT_NAME=todo-app
#   USE_WEB=yes
#   USE_IOS=no
#   USE_ANDROID=no
#   USE_DB=yes
#   DB_KIND=d1
#   USE_EMAIL=yes
#   USE_PLAYWRIGHT=yes
#   USE_MAESTRO=no
#   USE_CLAUDE_ACTION=yes
#   CLAUDE_AUTH=oauth
#   USE_GLOBAL_CLAUDE=yes
#   USE_GITHUB_ISSUES=yes

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ===== 引数パース =====
ROOT=""
CONFIG_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --help|-h)
      sed -n '1,/^set -euo pipefail/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) ROOT="$1"; shift ;;
  esac
done
ROOT="${ROOT:-$PWD}"
mkdir -p "$ROOT"
cd "$ROOT"

# ===== 対話 / 非対話の分岐 =====
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

if [ -n "$CONFIG_FILE" ]; then
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "::error:: --config で指定されたファイルがありません: $CONFIG_FILE" >&2
    exit 1
  fi
  echo "[bootstrap] 非対話モード: $CONFIG_FILE から読み込み"
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  PROJECT_NAME="${PROJECT_NAME:-$(basename "$ROOT")}"
  USE_WEB="${USE_WEB:-no}"
  USE_IOS="${USE_IOS:-no}"
  USE_ANDROID="${USE_ANDROID:-no}"
  USE_DB="${USE_DB:-no}"
  DB_KIND="${DB_KIND:-none}"
  USE_EMAIL="${USE_EMAIL:-no}"
  USE_PLAYWRIGHT="${USE_PLAYWRIGHT:-no}"
  USE_MAESTRO="${USE_MAESTRO:-no}"
  USE_CLAUDE_ACTION="${USE_CLAUDE_ACTION:-no}"
  CLAUDE_AUTH="${CLAUDE_AUTH:-oauth}"
  USE_GLOBAL_CLAUDE="${USE_GLOBAL_CLAUDE:-yes}"
  USE_GITHUB_ISSUES="${USE_GITHUB_ISSUES:-yes}"
else
  echo "=================================="
  echo " 汎用ハーネス ワンコマンドセットアップ"
  echo "=================================="
  echo "  作業ディレクトリ: $ROOT"
  echo

  PROJECT_NAME=$(ask "プロジェクト名" "$(basename "$ROOT")")

  echo
  echo "プラットフォームを選択（複数可、必要なものを y）"
  USE_WEB=$(ask_yn "  Web (Hono + React Email)" "y")
  USE_IOS=$(ask_yn "  iOS (Swift / SwiftUI)" "n")
  USE_ANDROID=$(ask_yn "  Android (Kotlin / Jetpack Compose)" "n")

  if [ "$USE_WEB" = "no" ] && [ "$USE_IOS" = "no" ] && [ "$USE_ANDROID" = "no" ]; then
    echo "::error:: 1 つ以上のプラットフォームを選択してください"
    exit 1
  fi

  echo
  echo "データベース"
  USE_DB=$(ask_yn "  DB を使う" "y")
  DB_KIND="none"
  if [ "$USE_DB" = "yes" ]; then
    echo "  選択: 1) Cloudflare D1 (推奨)  2) なし"
    DB_KIND=$(ask "  どれを使う？ (d1/none)" "d1")
  fi

  echo
  USE_EMAIL=$(ask_yn "メール機能（Resend、パスワードリセット含む）を使う" "n")

  echo
  USE_PLAYWRIGHT="no"; USE_MAESTRO="no"
  [ "$USE_WEB" = "yes" ] && USE_PLAYWRIGHT=$(ask_yn "E2E に Playwright を使う" "y")
  if [ "$USE_IOS" = "yes" ] || [ "$USE_ANDROID" = "yes" ]; then
    USE_MAESTRO=$(ask_yn "E2E に Maestro を使う" "y")
  fi

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

  echo
  echo "Claude のグローバル設定（~/.claude/CLAUDE.md, skills, agents）の扱い:"
  echo "  y = グローバルを引き継ぐ（個人の好みがそのまま効く、推奨）"
  echo "  n = プロジェクト内に独立配置"
  USE_GLOBAL_CLAUDE=$(ask_yn "Claude グローバル設定を引き継ぐ" "y")

  echo
  echo "タスク管理の方式:"
  echo "  y = GitHub Issue で管理（gh issue create で親/子 issue を起票）"
  echo "  n = ローカル管理（dev/docs/task/<id>.md にファイルとして保存）"
  USE_GITHUB_ISSUES=$(ask_yn "GitHub Issue 駆動で進める" "y")
fi

# ===== 設定保存（統一: .my-harness/.config）=====
mkdir -p .my-harness lanes
cat > .my-harness/.config <<EOF
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
USE_GLOBAL_CLAUDE=$USE_GLOBAL_CLAUDE
USE_GITHUB_ISSUES=$USE_GITHUB_ISSUES
EOF

echo
echo "=== 設定確定 ==="
cat .my-harness/.config
echo

# ===== 1. bare git の作成 =====
if [ ! -d .bare ]; then
  echo "[bootstrap] bare repository を初期化"
  git init --bare .bare
fi
[ -f .git ] || printf 'gitdir: ./.bare\n' > .git

# ===== 2. main / stage / dev ブランチを保証 =====
if ! git --git-dir=.bare rev-parse --verify refs/heads/main >/dev/null 2>&1; then
  echo "[bootstrap] 初期コミットと main ブランチを作成"
  git --git-dir=.bare symbolic-ref HEAD refs/heads/main
  git read-tree --empty
  EMPTY=$(git write-tree)
  INITIAL_COMMIT=$(git commit-tree "$EMPTY" -m "chore: initial commit")
  git update-ref refs/heads/main "$INITIAL_COMMIT"
fi

ensure_branch() {
  local branchName="$1"
  if ! git --git-dir=.bare rev-parse --verify "refs/heads/$branchName" >/dev/null 2>&1; then
    echo "[bootstrap] ブランチ '$branchName' を main から作成"
    git --git-dir=.bare branch "$branchName" main
  fi
}
ensure_branch stage
ensure_branch dev

# ===== 3. worktree =====
git worktree prune
ensure_worktree() {
  local name="$1"
  if [ -f "$name/.git" ]; then return 0; fi
  if [ -e "$name" ]; then
    echo "::warning:: '$name' が既に存在しますが worktree マーカが見つかりません。スキップ"
    return 0
  fi
  echo "[bootstrap] worktree '$name' を作成"
  git worktree add --force "$name" "$name"
}
ensure_worktree main
ensure_worktree stage
ensure_worktree dev

# ===== 4. 共通ファイル / プラットフォーム / Claude 設定 配布 =====
echo "[bootstrap] 共通ファイルを配布"
bash "$HARNESS_DIR/scripts/setup-common.sh" "$ROOT"

echo "[bootstrap] プラットフォーム別テンプレを配布"
bash "$HARNESS_DIR/scripts/setup-platforms.sh" "$ROOT"

echo "[bootstrap] Claude 設定を配置 (USE_GLOBAL_CLAUDE=$USE_GLOBAL_CLAUDE)"
bash "$HARNESS_DIR/scripts/setup-claude.sh" "$ROOT"

# ===== 5. ハーネス自体を dev/.my-harness にコピー =====
mkdir -p dev/.my-harness
rsync -a --exclude='.git' --exclude='.config' "$HARNESS_DIR/" dev/.my-harness/
cp .my-harness/.config dev/.my-harness/.config

# ===== 6. dev で初期 scaffold をコミット =====
if ! git -C dev log --oneline 2>/dev/null | grep -q "chore: harness scaffold"; then
  echo "[bootstrap] dev で初期 scaffold コミットを作成"
  ( cd dev
    git add -A
    if ! git diff --cached --quiet; then
      git -c user.name="harness-bot" -c user.email="harness@local" \
        commit --no-verify -m "chore: harness scaffold ($(grep -E 'USE_|DB_KIND' .my-harness/.config | tr '\n' ' '))"
    fi
  )
fi

cat <<EOS

==================================
 ハーネス構築完了
==================================
構成: web=$USE_WEB ios=$USE_IOS android=$USE_ANDROID db=$DB_KIND email=$USE_EMAIL
タスク管理: $([ "$USE_GITHUB_ISSUES" = "yes" ] && echo "GitHub Issue 駆動" || echo "ローカル docs/task/ 駆動")

次のステップ:

  cd $ROOT/dev
  direnv allow              # Nix shell へ自動切替
  pnpm install              # 依存関係
  pnpm exec husky           # husky 9.x セットアップ
  git remote add origin git@github.com:<owner>/<repo>.git
  git push --all origin     # main / stage / dev を一斉 push
  bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
  bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>

完成後:
  bash .my-harness/scripts/new-feature.sh <issue-number> <slug>

EOS
