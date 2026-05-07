#!/usr/bin/env bash
# Summary: One-command interactive harness setup.
#
# Usage:
#   bash bootstrap.sh <project-root>                    # interactive mode
#   bash bootstrap.sh <project-root> --config <file>    # non-interactive mode (called from /my-harness-init)
#
# Config file format (.my-harness/.config compatible, same schema as SKILL.md):
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
#   LANG (en|ja, default en)

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ===== Argument parsing =====
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

# ===== Interactive helpers =====
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
    echo "  → Please choose from: ${choices[*]}" >&2
  done
}

if [ -n "$CONFIG_FILE" ]; then
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "::error:: Config file specified with --config not found: $CONFIG_FILE" >&2
    exit 1
  fi
  echo "[bootstrap] Non-interactive mode: loading from $CONFIG_FILE"
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
  LANG="${LANG:-en}"
else
  echo "=================================="
  echo " Harness One-Command Setup"
  echo "=================================="
  echo "  Working directory: $ROOT"
  echo

  # Phase 0 — Language
  LANG=$(ask_choice "Output language for this project" "en" en ja)

  PROJECT_NAME=$(ask "Project name" "$(basename "$ROOT")")

  echo
  echo "── Platforms ──"
  USE_WEB=$(ask_yn "Build a Web app" "y")
  if [ "$USE_WEB" = "yes" ]; then
    WEB_KIND=$(ask_choice "  Framework" "nextjs" nextjs tanstack)
  else
    WEB_KIND=nextjs
  fi
  USE_IOS=$(ask_yn "Build an iOS app" "y")
  if [ "$USE_IOS" = "yes" ]; then
    IOS_KIND=$(ask_choice "  Implementation" "swift" swift expo flutter)
  else
    IOS_KIND=swift
  fi
  USE_ANDROID=$(ask_yn "Build an Android app" "y")
  if [ "$USE_ANDROID" = "yes" ]; then
    ANDROID_KIND=$(ask_choice "  Implementation" "kotlin" kotlin expo flutter)
  else
    ANDROID_KIND=kotlin
  fi
  USE_DESKTOP=$(ask_yn "Build a Desktop app" "y")
  if [ "$USE_DESKTOP" = "yes" ]; then
    DESKTOP_KIND=$(ask_choice "  Framework" "tauri" tauri electron)
    DESKTOP_OS=$(ask "  Target OS (comma-separated)" "macos,windows,linux")
  else
    DESKTOP_KIND=tauri
    DESKTOP_OS=macos,windows,linux
  fi

  if [ "$USE_WEB" = "no" ] && [ "$USE_IOS" = "no" ] && [ "$USE_ANDROID" = "no" ] && [ "$USE_DESKTOP" = "no" ]; then
    echo "::error:: Please select at least one platform" >&2
    exit 1
  fi

  echo
  echo "── Backend ──"
  USE_BACKEND=$(ask_yn "Build a backend" "y")
  if [ "$USE_BACKEND" = "yes" ]; then
    BACKEND_KIND=$(ask_choice "  Language/Framework" "hono" hono gin rust)
  else
    BACKEND_KIND=hono
  fi
  USE_DB=$(ask_yn "Use a database" "y")
  if [ "$USE_DB" = "yes" ]; then
    DB_KIND=$(ask_choice "  Database type" "d1" d1 postgres mysql sqlite)
  else
    DB_KIND=d1
  fi
  USE_EMAIL=$(ask_yn "Use email (Resend, including password reset)" "n")
  AUTH_KIND=$(ask_choice "Authentication level" "none" none password oauth)

  echo
  echo "── Tests / CI ──"
  E2E_SCOPE=$(ask_choice "E2E scope" "web" web mobile both none)
  USE_CLAUDE_ACTION=$(ask_yn "Use Claude Code Action for PR review" "y")
  if [ "$USE_CLAUDE_ACTION" = "yes" ]; then
    CLAUDE_AUTH=$(ask_choice "  Auth method" "oauth" api oauth)
  else
    CLAUDE_AUTH=oauth
  fi

  echo
  echo "── Codex integration (optional) ──"
  USE_CODEX=$(ask_yn "Use Codex integration (second opinion / image generation / subagent delegation)" "n")
  if [ "$USE_CODEX" = "yes" ]; then
    CODEX_SESSION=$(ask "  Codex session name" "my-harness-init")
    USE_CODEX_ENGINEER=$(ask_yn "  Delegate engineer to Codex" "y")
    USE_CODEX_E2E_REVIEWER=$(ask_yn "  Delegate e2e-reviewer to Codex" "y")
    USE_CODEX_REVIEWER=$(ask_yn "  Delegate reviewer to Codex" "y")
    ON_CODEX_AUTH_FAIL=$(ask_choice "  Behavior on auth/subscription failure" "pause" pause fail)
  else
    CODEX_SESSION=my-harness-init
    USE_CODEX_ENGINEER=no
    USE_CODEX_E2E_REVIEWER=no
    USE_CODEX_REVIEWER=no
    ON_CODEX_AUTH_FAIL=pause
  fi

  echo
  echo "── Other ──"
  USE_GLOBAL_CLAUDE=$(ask_yn "Inherit global Claude settings" "y")
  USE_GITHUB_ISSUES=$(ask_yn "Use GitHub Issue-driven workflow (n = local docs/task/)" "y")
fi

# ===== Derive USE_PLAYWRIGHT / USE_MAESTRO from E2E_SCOPE =====
case "${E2E_SCOPE:-web}" in
  web)         USE_PLAYWRIGHT=yes; USE_MAESTRO=no  ;;
  mobile)      USE_PLAYWRIGHT=no;  USE_MAESTRO=yes ;;
  both)        USE_PLAYWRIGHT=yes; USE_MAESTRO=yes ;;
  none|*)      USE_PLAYWRIGHT=no;  USE_MAESTRO=no  ;;
esac

# ===== When USE_CODEX=no, force individual flags to no (master switch takes priority) =====
if [ "$USE_CODEX" != "yes" ]; then
  USE_CODEX_ENGINEER=no
  USE_CODEX_E2E_REVIEWER=no
  USE_CODEX_REVIEWER=no
fi

# ===== Save configuration (.my-harness/.config) =====
mkdir -p .my-harness lanes
cat > .my-harness/.config <<EOF
PROJECT_NAME=$PROJECT_NAME
ROOT=$ROOT
LANG=${LANG:-en}
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
echo "=== Configuration confirmed ==="
cat .my-harness/.config
echo

# ===== 1. Create bare git repository =====
if [ ! -d .bare ]; then
  echo "[bootstrap] Initializing bare repository"
  git init --bare .bare
fi
[ -f .git ] || printf 'gitdir: ./.bare\n' > .git

# ===== 2. Ensure main / stage / dev branches exist =====
if ! git --git-dir=.bare rev-parse --verify refs/heads/main >/dev/null 2>&1; then
  echo "[bootstrap] Creating initial commit and main branch"
  git --git-dir=.bare symbolic-ref HEAD refs/heads/main
  git read-tree --empty
  EMPTY=$(git write-tree)
  INITIAL_COMMIT=$(git commit-tree "$EMPTY" -m "chore: initial commit")
  git update-ref refs/heads/main "$INITIAL_COMMIT"
fi

ensure_branch() {
  local branchName="$1"
  if ! git --git-dir=.bare rev-parse --verify "refs/heads/$branchName" >/dev/null 2>&1; then
    echo "[bootstrap] Creating branch '$branchName' from main"
    git --git-dir=.bare branch "$branchName" main
  fi
}
ensure_branch stage
ensure_branch dev

# ===== 3. Worktrees =====
git worktree prune
ensure_worktree() {
  local name="$1"
  if [ -f "$name/.git" ]; then return 0; fi
  if [ -e "$name" ]; then
    echo "::warning:: '$name' already exists but no worktree marker found. Skipping."
    return 0
  fi
  echo "[bootstrap] Creating worktree '$name'"
  git worktree add --force "$name" "$name"
}
ensure_worktree main
ensure_worktree stage
ensure_worktree dev

# ===== 4. Distribute common files / platform templates / Claude config =====
echo "[bootstrap] Distributing common files"
bash "$HARNESS_DIR/scripts/setup-common.sh" "$ROOT"

echo "[bootstrap] Distributing platform-specific templates"
bash "$HARNESS_DIR/scripts/setup-platforms.sh" "$ROOT"


# ===== 5. Copy harness itself to dev/.my-harness =====
mkdir -p dev/.my-harness
rsync -a --exclude='.git' --exclude='.config' "$HARNESS_DIR/" dev/.my-harness/
cp .my-harness/.config dev/.my-harness/.config

# ===== 6. Commit initial scaffold on dev =====
if ! git -C dev log --oneline 2>/dev/null | grep -q "chore: harness scaffold"; then
  echo "[bootstrap] Creating initial scaffold commit on dev"
  ( cd dev
    git add -A
    if ! git diff --cached --quiet; then
      git -c user.name="harness-bot" -c user.email="harness@local" \
        commit --no-verify -m "chore: harness scaffold ($(grep -E 'USE_|_KIND' .my-harness/.config | tr '\n' ' '))"
    fi
  )
fi

# ===== 7. Write init-state.json (for resume support in /my-harness-init) =====
mkdir -p .my-harness
cat > .my-harness/init-state.json <<EOF
{
  "schema_version": "1",
  "project_name": "$PROJECT_NAME",
  "root": "$ROOT",
  "projectLang": "${LANG:-en}",
  "current_phase": "bootstrap-completed",
  "phases_completed": ["language", "setup", "what", "platform", "backend", "data-model", "visual", "bootstrap"],
  "next_action": "issue-task-generation",
  "next_action_command": "Continue /my-harness-init (proceed to phase 6.3 issue/task generation)",
  "working_directory": "$ROOT",
  "resume_after_bootstrap_directory": "$ROOT/dev",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
echo "[bootstrap] init-state.json written → .my-harness/init-state.json"

cat <<EOS

==================================
 Harness setup complete
==================================
Configuration:
  Web=$USE_WEB ($WEB_KIND)  iOS=$USE_IOS ($IOS_KIND)
  Android=$USE_ANDROID ($ANDROID_KIND)  Desktop=$USE_DESKTOP ($DESKTOP_KIND)
  Backend=$USE_BACKEND ($BACKEND_KIND)  DB=$USE_DB ($DB_KIND)
  Auth=$AUTH_KIND  E2E=$E2E_SCOPE
  Codex=$USE_CODEX (engineer=$USE_CODEX_ENGINEER e2e=$USE_CODEX_E2E_REVIEWER reviewer=$USE_CODEX_REVIEWER)
  Language=$LANG
Task management: $([ "$USE_GITHUB_ISSUES" = "yes" ] && echo "GitHub Issue-driven" || echo "Local docs/task/-driven")

Next steps (run in terminal):

  cd $ROOT/dev
  direnv allow
  pnpm install
  pnpm exec husky

  git remote add origin git@github.com:<owner>/<repo>.git
  git push --all origin
  bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
  bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>

Then restart Claude Code under dev/ and in a new session run:

  /harness-team-lead              # Run all 4 lanes in parallel (recommended)
  /harness-new-feature <issue#>   # Start an individual feature
  /my-harness-init                # Resume from a checkpoint (auto-detects init-state.json)

EOS
