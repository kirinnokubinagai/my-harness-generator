#!/usr/bin/env bash
# 概要: ハーネスのワンコマンド対話セットアップ。
#
# 使い方:
#   bash bootstrap.sh <project-root>                    # 対話モード
#   bash bootstrap.sh <project-root> --config <file>    # 非対話モード（/my-harness-init から呼ぶ）
#
# 設定ファイル形式（.my-harness/.config 互換、SKILL.md と同じスキーマ）:
#   PROJECT_NAME / ROOT
#   USE_WEB + WEB_KIND (nextjs|tanstack)
#   USE_IOS + IOS_KIND (swift|expo|flutter)
#   USE_ANDROID + ANDROID_KIND (kotlin|expo|flutter)
#   USE_DESKTOP + DESKTOP_KIND (tauri|electron) + DESKTOP_OS
#   USE_BACKEND + BACKEND_KIND (hono|gin|rust)
#   USE_DB + DB_KIND (d1|postgres|mysql|sqlite)
#   USE_EMAIL / AUTH_KIND (none|password|oauth)
#   E2E_SCOPE (web|mobile|both|none) → derive USE_PLAYWRIGHT / USE_MAESTRO
#   USE_CLAUDE_ACTION / CLAUDE_AUTH (api|oauth)
#   USE_CODEX + USE_CODEX_ENGINEER + USE_CODEX_E2E_REVIEWER + USE_CODEX_REVIEWER
#   CODEX_SESSION / ON_CODEX_AUTH_FAIL (pause|fail)
#   USE_GLOBAL_CLAUDE / USE_GITHUB_ISSUES

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

# ===== 対話 helpers =====
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
ask_choice() {
  local prompt="$1"; local default="$2"; shift 2
  local choices=("$@") c a
  while :; do
    a=$(ask "$prompt ($(IFS=/; echo "${choices[*]}"))" "$default")
    for c in "${choices[@]}"; do
      [ "$a" = "$c" ] && { echo "$c"; return; }
    done
    echo "  → 下記から選んでください: ${choices[*]}" >&2
  done
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
  USE_WEB="${USE_WEB:-yes}"
  WEB_KIND="${WEB_KIND:-nextjs}"
  USE_IOS="${USE_IOS:-yes}"
  IOS_KIND="${IOS_KIND:-swift}"
  USE_ANDROID="${USE_ANDROID:-yes}"
  ANDROID_KIND="${ANDROID_KIND:-kotlin}"
  USE_DESKTOP="${USE_DESKTOP:-yes}"
  DESKTOP_KIND="${DESKTOP_KIND:-tauri}"
  DESKTOP_OS="${DESKTOP_OS:-macos,windows,linux}"
  USE_BACKEND="${USE_BACKEND:-yes}"
  BACKEND_KIND="${BACKEND_KIND:-hono}"
  USE_DB="${USE_DB:-yes}"
  DB_KIND="${DB_KIND:-d1}"
  USE_EMAIL="${USE_EMAIL:-no}"
  AUTH_KIND="${AUTH_KIND:-none}"
  E2E_SCOPE="${E2E_SCOPE:-web}"
  USE_CLAUDE_ACTION="${USE_CLAUDE_ACTION:-yes}"
  CLAUDE_AUTH="${CLAUDE_AUTH:-oauth}"
  USE_CODEX="${USE_CODEX:-no}"
  CODEX_SESSION="${CODEX_SESSION:-my-harness-init}"
  USE_CODEX_ENGINEER="${USE_CODEX_ENGINEER:-no}"
  USE_CODEX_E2E_REVIEWER="${USE_CODEX_E2E_REVIEWER:-no}"
  USE_CODEX_REVIEWER="${USE_CODEX_REVIEWER:-no}"
  ON_CODEX_AUTH_FAIL="${ON_CODEX_AUTH_FAIL:-pause}"
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
  echo "── プラットフォーム ──"
  USE_WEB=$(ask_yn "Web を作る" "y")
  if [ "$USE_WEB" = "yes" ]; then
    WEB_KIND=$(ask_choice "  フレームワーク" "nextjs" nextjs tanstack)
  else
    WEB_KIND=nextjs
  fi
  USE_IOS=$(ask_yn "iOS を作る" "y")
  if [ "$USE_IOS" = "yes" ]; then
    IOS_KIND=$(ask_choice "  実装" "swift" swift expo flutter)
  else
    IOS_KIND=swift
  fi
  USE_ANDROID=$(ask_yn "Android を作る" "y")
  if [ "$USE_ANDROID" = "yes" ]; then
    ANDROID_KIND=$(ask_choice "  実装" "kotlin" kotlin expo flutter)
  else
    ANDROID_KIND=kotlin
  fi
  USE_DESKTOP=$(ask_yn "Desktop を作る" "y")
  if [ "$USE_DESKTOP" = "yes" ]; then
    DESKTOP_KIND=$(ask_choice "  フレームワーク" "tauri" tauri electron)
    DESKTOP_OS=$(ask "  対応 OS（カンマ区切り）" "macos,windows,linux")
  else
    DESKTOP_KIND=tauri
    DESKTOP_OS=macos,windows,linux
  fi

  if [ "$USE_WEB" = "no" ] && [ "$USE_IOS" = "no" ] && [ "$USE_ANDROID" = "no" ] && [ "$USE_DESKTOP" = "no" ]; then
    echo "::error:: 1 つ以上のプラットフォームを選択してください" >&2
    exit 1
  fi

  echo
  echo "── バックエンド ──"
  USE_BACKEND=$(ask_yn "バックエンドを作る" "y")
  if [ "$USE_BACKEND" = "yes" ]; then
    BACKEND_KIND=$(ask_choice "  言語/フレームワーク" "hono" hono gin rust)
  else
    BACKEND_KIND=hono
  fi
  USE_DB=$(ask_yn "DB を使う" "y")
  if [ "$USE_DB" = "yes" ]; then
    DB_KIND=$(ask_choice "  DB の種類" "d1" d1 postgres mysql sqlite)
  else
    DB_KIND=d1
  fi
  USE_EMAIL=$(ask_yn "メール（Resend、パスワードリセット含む）を使う" "n")
  AUTH_KIND=$(ask_choice "認証どこまで" "none" none password oauth)

  echo
  echo "── テスト / CI ──"
  E2E_SCOPE=$(ask_choice "E2E スコープ" "web" web mobile both none)
  USE_CLAUDE_ACTION=$(ask_yn "PR レビューに Claude Code Action を使う" "y")
  if [ "$USE_CLAUDE_ACTION" = "yes" ]; then
    CLAUDE_AUTH=$(ask_choice "  認証方式" "oauth" api oauth)
  else
    CLAUDE_AUTH=oauth
  fi

  echo
  echo "── Codex 連携（任意）──"
  USE_CODEX=$(ask_yn "Codex 連携を使う（第二意見・画像生成・subagent 委譲）" "n")
  if [ "$USE_CODEX" = "yes" ]; then
    CODEX_SESSION=$(ask "  Codex session 名" "my-harness-init")
    USE_CODEX_ENGINEER=$(ask_yn "  engineer を Codex に任せる" "y")
    USE_CODEX_E2E_REVIEWER=$(ask_yn "  e2e-reviewer を Codex に任せる" "y")
    USE_CODEX_REVIEWER=$(ask_yn "  reviewer を Codex に任せる" "y")
    ON_CODEX_AUTH_FAIL=$(ask_choice "  認証/サブスク切れ時の挙動" "pause" pause fail)
  else
    CODEX_SESSION=my-harness-init
    USE_CODEX_ENGINEER=no
    USE_CODEX_E2E_REVIEWER=no
    USE_CODEX_REVIEWER=no
    ON_CODEX_AUTH_FAIL=pause
  fi

  echo
  echo "── その他 ──"
  USE_GLOBAL_CLAUDE=$(ask_yn "Claude グローバル設定を引き継ぐ" "y")
  USE_GITHUB_ISSUES=$(ask_yn "GitHub Issue 駆動で進める（n ならローカル docs/task/）" "y")
fi

# ===== USE_PLAYWRIGHT / USE_MAESTRO を E2E_SCOPE から派生 =====
case "${E2E_SCOPE:-web}" in
  web)         USE_PLAYWRIGHT=yes; USE_MAESTRO=no  ;;
  mobile)      USE_PLAYWRIGHT=no;  USE_MAESTRO=yes ;;
  both)        USE_PLAYWRIGHT=yes; USE_MAESTRO=yes ;;
  none|*)      USE_PLAYWRIGHT=no;  USE_MAESTRO=no  ;;
esac

# ===== USE_CODEX=no のとき個別フラグも強制 no（master switch 優先）=====
if [ "$USE_CODEX" != "yes" ]; then
  USE_CODEX_ENGINEER=no
  USE_CODEX_E2E_REVIEWER=no
  USE_CODEX_REVIEWER=no
fi

# ===== 設定保存（統一: .my-harness/.config）=====
mkdir -p .my-harness lanes
cat > .my-harness/.config <<EOF
PROJECT_NAME=$PROJECT_NAME
ROOT=$ROOT
USE_WEB=$USE_WEB
WEB_KIND=$WEB_KIND
USE_IOS=$USE_IOS
IOS_KIND=$IOS_KIND
USE_ANDROID=$USE_ANDROID
ANDROID_KIND=$ANDROID_KIND
USE_DESKTOP=$USE_DESKTOP
DESKTOP_KIND=$DESKTOP_KIND
DESKTOP_OS=$DESKTOP_OS
USE_BACKEND=$USE_BACKEND
BACKEND_KIND=$BACKEND_KIND
USE_DB=$USE_DB
DB_KIND=$DB_KIND
USE_EMAIL=$USE_EMAIL
AUTH_KIND=$AUTH_KIND
E2E_SCOPE=$E2E_SCOPE
USE_PLAYWRIGHT=$USE_PLAYWRIGHT
USE_MAESTRO=$USE_MAESTRO
USE_CLAUDE_ACTION=$USE_CLAUDE_ACTION
CLAUDE_AUTH=$CLAUDE_AUTH
USE_CODEX=$USE_CODEX
CODEX_SESSION=$CODEX_SESSION
USE_CODEX_ENGINEER=$USE_CODEX_ENGINEER
USE_CODEX_E2E_REVIEWER=$USE_CODEX_E2E_REVIEWER
USE_CODEX_REVIEWER=$USE_CODEX_REVIEWER
ON_CODEX_AUTH_FAIL=$ON_CODEX_AUTH_FAIL
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
        commit --no-verify -m "chore: harness scaffold ($(grep -E 'USE_|_KIND' .my-harness/.config | tr '\n' ' '))"
    fi
  )
fi

# ===== 7. init-state.json を書き出し（/my-harness-init からの再開用）=====
mkdir -p .my-harness
cat > .my-harness/init-state.json <<EOF
{
  "schema_version": "1",
  "project_name": "$PROJECT_NAME",
  "root": "$ROOT",
  "current_phase": "bootstrap-completed",
  "phases_completed": ["setup", "what", "platform", "backend", "data-model", "visual", "bootstrap"],
  "next_action": "issue-task-generation",
  "next_action_command": "/my-harness-init を継続（フェーズ 6.3 issue/task 生成へ）",
  "working_directory": "$ROOT",
  "resume_after_bootstrap_directory": "$ROOT/dev",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
echo "[bootstrap] init-state.json を書き出し → .my-harness/init-state.json"

cat <<EOS

==================================
 ハーネス構築完了
==================================
構成:
  Web=$USE_WEB ($WEB_KIND)  iOS=$USE_IOS ($IOS_KIND)
  Android=$USE_ANDROID ($ANDROID_KIND)  Desktop=$USE_DESKTOP ($DESKTOP_KIND)
  Backend=$USE_BACKEND ($BACKEND_KIND)  DB=$USE_DB ($DB_KIND)
  Auth=$AUTH_KIND  E2E=$E2E_SCOPE
  Codex=$USE_CODEX (engineer=$USE_CODEX_ENGINEER e2e=$USE_CODEX_E2E_REVIEWER reviewer=$USE_CODEX_REVIEWER)
タスク管理: $([ "$USE_GITHUB_ISSUES" = "yes" ] && echo "GitHub Issue 駆動" || echo "ローカル docs/task/ 駆動")

次のステップ（ターミナルで実行）:

  cd $ROOT/dev
  direnv allow
  pnpm install
  pnpm exec husky

  git remote add origin git@github.com:<owner>/<repo>.git
  git push --all origin
  bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
  bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>

そして dev/ 配下で Claude Code を再起動し、新セッションで:

  /harness-team-lead              # 4 レーン並列で issue 一気に進める（推奨）
  /harness-new-feature <issue#>   # 個別 feature 着手
  /my-harness-init                # 中断からの再開（init-state.json 自動検出）

EOS
