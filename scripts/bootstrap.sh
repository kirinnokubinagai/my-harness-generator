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
#   USE_CODEX + USE_CODEX_ANALYST + USE_CODEX_ENGINEER + USE_CODEX_E2E_REVIEWER + USE_CODEX_REVIEWER
#   CODEX_SESSION / ON_CODEX_AUTH_FAIL (pause|fail)
#   USE_GITHUB_ISSUES
#   USE_GLOBAL_CLAUDE (yes|no, default yes) — no writes dev/.claude/settings.json with claudeMdExcludes
#   LANG (en|ja, default en)
#   PACKAGE_MANAGER (pnpm|bun|npm|yarn, default pnpm) — used in install/exec lines, flake.nix, husky setup, CI workflows
#   ARCHITECTURE (client-server|client-serverless|p2p-pure|p2p-hybrid, default client-server)
#                — p2p-pure skips backend bootstrap entirely; p2p-hybrid writes a minimal coordinator/bootstrap stub

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Library helpers
# shellcheck disable=SC1091
. "$HARNESS_DIR/scripts/lib/rsync-excludes.sh"

# copy_if_absent <src-glob> <dst-dir>
# Copy each file matching the glob into dst-dir, skipping files that already
# exist there. Non-destructive: user-edited dest files are preserved.
copy_if_absent() {
  local glob="$1" dst="$2" f name
  mkdir -p "$dst"
  for f in $glob; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [ -f "$dst/$name" ] || cp "$f" "$dst/$name"
  done
}

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
  USE_CODEX_ANALYST="${USE_CODEX_ANALYST:-no}"
  USE_CODEX_ENGINEER="${USE_CODEX_ENGINEER:-no}"
  USE_CODEX_E2E_REVIEWER="${USE_CODEX_E2E_REVIEWER:-no}"
  USE_CODEX_REVIEWER="${USE_CODEX_REVIEWER:-no}"
  MAX_LANES="${MAX_LANES:-4}"
  ON_CODEX_AUTH_FAIL="${ON_CODEX_AUTH_FAIL:-pause}"
  USE_GITHUB_ISSUES="${USE_GITHUB_ISSUES:-yes}"
  USE_GLOBAL_CLAUDE="${USE_GLOBAL_CLAUDE:-yes}"
  LANG="${LANG:-en}"
  PACKAGE_MANAGER="${PACKAGE_MANAGER:-pnpm}"
  ARCHITECTURE="${ARCHITECTURE:-client-server}"
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
    USE_CODEX_ANALYST=$(ask_yn "  Delegate analyst (brief / commit msg / PR body) to Codex" "y")
    USE_CODEX_ENGINEER=$(ask_yn "  Delegate engineer (file edits via codex exec --sandbox workspace-write) to Codex" "y")
    USE_CODEX_E2E_REVIEWER=$(ask_yn "  Delegate e2e-reviewer failure-report synthesis to Codex (test execution stays local)" "n")
    USE_CODEX_REVIEWER=$(ask_yn "  Delegate reviewer (codex exec --sandbox read-only) to Codex" "y")
    ON_CODEX_AUTH_FAIL=$(ask_choice "  Behavior on auth/subscription failure" "pause" pause fail)
  else
    CODEX_SESSION=my-harness-init
    USE_CODEX_ANALYST=no
    USE_CODEX_ENGINEER=no
    USE_CODEX_E2E_REVIEWER=no
    USE_CODEX_REVIEWER=no
    ON_CODEX_AUTH_FAIL=pause
  fi

  echo "── Parallelism (auto-suggested from system RAM) ──"
  # Use scripts/lib/recommend-lanes.sh — accounts for macOS memory compression
  # (+33% effective), swap, and current memory_pressure. The runtime gate
  # (spawn-lane-decision.sh) is still the source of truth at spawn time;
  # MAX_LANES is just the ceiling.
  # shellcheck disable=SC1091
  . "$HARNESS_DIR/scripts/lib/recommend-lanes.sh"
  REC_RAW=$(recommend_lanes)
  LANE_SUGGEST="${REC_RAW%%|*}"
  REC_DETAIL="${REC_RAW#*|}"
  TOTAL_RAM_GB=$(detect_total_ram_gb)
  echo "  ${REC_DETAIL}"
  MAX_LANES=$(ask "Maximum concurrent lanes 1-4 (recommended ${LANE_SUGGEST}; runtime gate checks live RAM/swap/compressor)" "$LANE_SUGGEST")
  case "$MAX_LANES" in
    1|2|3|4) : ;;
    *)
      echo "  → MAX_LANES must be 1..4 — falling back to recommended $LANE_SUGGEST" >&2
      MAX_LANES=$LANE_SUGGEST
      ;;
  esac
  # Auto-tune per-lane RAM threshold so the spawn gate refuses additional lanes
  # before the machine runs out of headroom. Reserve 4 GB for the OS / Claude
  # Code itself, divide the rest by MAX_LANES. Floor at 2048 MB.
  LANE_RAM_MB=$(( (TOTAL_RAM_GB * 1024 - 4096) / MAX_LANES ))
  [ "$LANE_RAM_MB" -lt 2048 ] && LANE_RAM_MB=2048

  echo
  echo "── Other ──"
  USE_GITHUB_ISSUES=$(ask_yn "Use GitHub Issue-driven workflow (n = local docs/task/)" "y")
  USE_GLOBAL_CLAUDE=$(ask_yn "Inherit global ~/.claude/CLAUDE.md in this project (n = write claudeMdExcludes to dev/.claude/settings.json)" "y")
  PACKAGE_MANAGER=$(ask_choice "Node package manager" "pnpm" pnpm bun npm yarn)
  ARCHITECTURE=$(ask_choice "Overall architecture" "client-server" client-server client-serverless p2p-pure p2p-hybrid)
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
  USE_CODEX_ANALYST=no
  USE_CODEX_ENGINEER=no
  USE_CODEX_E2E_REVIEWER=no
  USE_CODEX_REVIEWER=no
fi

# ===== Architecture-driven adjustments =====
# p2p-pure: no central backend at all (skip backend bootstrap entirely).
# p2p-hybrid: backend remains but is a lightweight coordinator/bootstrap server.
case "${ARCHITECTURE:-client-server}" in
  p2p-pure)
    USE_BACKEND=no
    ;;
  p2p-hybrid)
    # Keep backend on, treat as coordinator (labeled later in scaffold).
    USE_BACKEND=yes
    ;;
  *) : ;;
esac

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
USE_CODEX_ANALYST=$USE_CODEX_ANALYST
USE_CODEX_ENGINEER=$USE_CODEX_ENGINEER
USE_CODEX_E2E_REVIEWER=$USE_CODEX_E2E_REVIEWER
USE_CODEX_REVIEWER=$USE_CODEX_REVIEWER
MAX_LANES=$MAX_LANES
HARNESS_LANE_RAM_MB=${LANE_RAM_MB:-4096}
HARNESS_LANE_SWAP_MAX_MB=${HARNESS_LANE_SWAP_MAX_MB:-1024}
HARNESS_LANE_COMP_MAX_MB=${HARNESS_LANE_COMP_MAX_MB:-6144}
ON_CODEX_AUTH_FAIL=$ON_CODEX_AUTH_FAIL
USE_GITHUB_ISSUES=$USE_GITHUB_ISSUES
USE_GLOBAL_CLAUDE=${USE_GLOBAL_CLAUDE:-yes}
PACKAGE_MANAGER=${PACKAGE_MANAGER:-pnpm}
ARCHITECTURE=${ARCHITECTURE:-client-server}
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
    # An existing non-worktree path is suspicious — it means a previous
    # half-completed bootstrap left a stub directory. Refuse to silently
    # skip it, otherwise the caller ends up missing a worktree they
    # asked for and only realizes much later (e.g. when running
    # /harness-team-lead). Tell the user explicitly so they can rm it
    # and re-run.
    echo "::error:: '$name' already exists but is not a git worktree." >&2
    echo "::error::   delete it (rm -rf $name) and re-run bootstrap." >&2
    return 1
  fi
  echo "[bootstrap] Creating worktree '$name'"
  git worktree add --force "$name" "$name"
}
ensure_worktree main
ensure_worktree stage
ensure_worktree dev

# Sanity check: all three must be live worktrees before we proceed. This
# catches the case where one of the ensure_worktree calls succeeded with a
# warning we missed (e.g. git printing a warning to stderr but exiting 0).
for wt in main stage dev; do
  if [ ! -f "$wt/.git" ]; then
    echo "::error:: worktree '$wt' is missing after setup. Cannot continue." >&2
    echo "::error::   git worktree list output:" >&2
    git worktree list >&2 || true
    exit 1
  fi
done
echo "[bootstrap] worktrees verified: main / stage / dev"

# ===== 4. Distribute common files / platform templates / Claude config =====
echo "[bootstrap] Distributing common files"
bash "$HARNESS_DIR/scripts/setup-common.sh" "$ROOT"

echo "[bootstrap] Distributing platform-specific templates"
bash "$HARNESS_DIR/scripts/setup-platforms.sh" "$ROOT"

# ===== 4.5. Template projet-name substitution =====
# wrangler.jsonc / alchemy.run.ts / lighthouserc.json には "harness" / "harness-app"
# のプレースホルダが入っている。bootstrap 時点で PROJECT_NAME に置換しておく。
SAFE_NAME=$(printf '%s' "${PROJECT_NAME:-harness}" | tr -c 'A-Za-z0-9-' '-' | sed 's/^-//; s/-$//')
SAFE_NAME=${SAFE_NAME:-harness}
for f in dev/wrangler.jsonc dev/alchemy.run.ts dev/lighthouserc.json; do
  [ -f "$f" ] || continue
  sed -i.bak \
    -e "s/\"harness-app\"/\"${SAFE_NAME}-app\"/g" \
    -e "s/\"harness\"/\"${SAFE_NAME}\"/g" \
    -e "s/harness-dev-/${SAFE_NAME}-dev-/g" \
    -e "s/harness-stage-/${SAFE_NAME}-stage-/g" \
    -e "s/harness-prod-/${SAFE_NAME}-prod-/g" \
    "$f"
  rm -f "$f.bak"
done

# ===== 4a. Production templates (runbooks + CI workflows + Hono middleware) =====
echo "[bootstrap] Distributing production templates"
# shellcheck disable=SC1091
. "$HARNESS_DIR/scripts/lib/distribute-production.sh"
distribute_production_templates

# learnings ファイル + secrets ガイドを dev/.my-harness/ へ配布 (初回のみ)
mkdir -p dev/.my-harness dev/secrets
[ -f "dev/.my-harness/learnings.md" ] || cp "$HARNESS_DIR/templates/dotmyharness/learnings.md" dev/.my-harness/learnings.md 2>/dev/null || true
[ -f "dev/secrets/README.md" ] || cp "$HARNESS_DIR/templates/dotmyharness/secrets-README.md" dev/secrets/README.md 2>/dev/null || true


# ===== 5. Copy harness itself to dev/.my-harness =====
mkdir -p dev/.my-harness
# Patterns live in scripts/lib/rsync-excludes.sh. Only runtime-needed files
# (rules/, scripts/, docs/) ship to the project tree; agents/, skills/, hooks/,
# templates/, nix/, .claude-plugin/ stay in $CLAUDE_PLUGIN_ROOT.
harness_rsync "$HARNESS_DIR/" dev/.my-harness/
cp .my-harness/.config dev/.my-harness/.config

# ===== 5a. Generate dev/CLAUDE.md and dev/AGENTS.md (shared rule entry point) =====
# Single source of truth: templates/CLAUDE.md.tmpl. The same content lands in both
# files so Claude Code reads dev/CLAUDE.md and Codex CLI / Cursor / Aider read
# dev/AGENTS.md. Both tools end up loading the rules under .my-harness/rules/.
TMPL="$HARNESS_DIR/templates/CLAUDE.md.tmpl"
if [ -f "$TMPL" ]; then
  sed \
    -e "s|\${PROJECT_NAME}|${PROJECT_NAME:-project}|g" \
    -e "s|\${LANG}|${LANG:-en}|g" \
    -e "s|\${ROOT}|$ROOT|g" \
    "$TMPL" > dev/CLAUDE.md
  cp dev/CLAUDE.md dev/AGENTS.md
  echo "[bootstrap] generated dev/CLAUDE.md and dev/AGENTS.md from templates/CLAUDE.md.tmpl"
else
  echo "::warning:: $TMPL not found — dev/CLAUDE.md and dev/AGENTS.md NOT generated" >&2
fi

# ===== 5a. P2P scaffold =====
# When ARCHITECTURE is p2p-pure or p2p-hybrid, drop a placeholder so the
# /harness-team-lead phase can pick the right transport (libp2p / Iroh / Hypercore)
# based on the chosen platforms. The actual library is selected later — here we
# just persist the architectural intent and a README explaining what comes next.
case "${ARCHITECTURE:-client-server}" in
  p2p-pure|p2p-hybrid)
    mkdir -p dev/p2p
    if [ ! -f dev/p2p/README.md ]; then
      cat > dev/p2p/README.md <<EOF
# P2P transport (placeholder)

ARCHITECTURE: ${ARCHITECTURE}

This directory is a placeholder. The actual P2P transport library (libp2p for
web/Node, Iroh for Rust, Hypercore for Node, or platform-specific equivalents)
will be selected at \`/harness-team-lead\` time based on the chosen platforms
and the persistence model.

What is decided right now:
- ARCHITECTURE = ${ARCHITECTURE}
  - p2p-pure  : no central server. All state replicates peer-to-peer.
  - p2p-hybrid: peers connect through a lightweight coordinator/bootstrap server
                (\`dev/server/\` if BACKEND_KIND was chosen) for discovery and
                rendezvous; data still flows peer-to-peer.

What is decided at /harness-team-lead time:
- Transport choice (libp2p / Iroh / Hypercore / WebRTC + DHT / etc.)
- Identity model (Ed25519 keypair on first run / DID / external auth)
- Replication model (CRDT / OT / log-based / file-based)
- Discovery (mDNS / DHT / known-peer list / coordinator)

Do not write transport code into this directory until those decisions land.
EOF
    fi
    ;;
esac

# ===== 5b. Write dev/.claude/settings.json when USE_GLOBAL_CLAUDE=no =====
if [ "${USE_GLOBAL_CLAUDE:-yes}" = "no" ]; then
  # Resolve absolute path to user's global CLAUDE.md.
  GLOBAL_CLAUDE_MD="${HOME}/.claude/CLAUDE.md"

  # Write project-scope settings.json (or merge into existing) so Claude Code
  # excludes the user-level CLAUDE.md when sessions start under dev/.
  PROJECT_SETTINGS="dev/.claude/settings.json"
  mkdir -p "dev/.claude"
  if [ -f "$PROJECT_SETTINGS" ]; then
    # Merge: keep existing fields, add/override claudeMdExcludes.
    tmp=$(mktemp)
    jq --arg path "$GLOBAL_CLAUDE_MD" \
       '.claudeMdExcludes = ((.claudeMdExcludes // []) + [$path] | unique)' \
       "$PROJECT_SETTINGS" > "$tmp" && mv "$tmp" "$PROJECT_SETTINGS"
  else
    cat > "$PROJECT_SETTINGS" <<EOF
{
  "claudeMdExcludes": [
    "$GLOBAL_CLAUDE_MD"
  ]
}
EOF
  fi
  echo "Configured dev/.claude/settings.json to exclude ~/.claude/CLAUDE.md (USE_GLOBAL_CLAUDE=no)"
fi

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

# ===== Compute package-manager invocations for the banner =====
PM="${PACKAGE_MANAGER:-pnpm}"
case "$PM" in
  bun)
    PM_INSTALL="bun install"
    PM_EXEC="bun"
    ;;
  npm)
    PM_INSTALL="npm install"
    PM_EXEC="npm exec"
    ;;
  yarn)
    PM_INSTALL="yarn install"
    PM_EXEC="yarn"
    ;;
  pnpm|*)
    PM_INSTALL="pnpm install"
    PM_EXEC="pnpm exec"
    ;;
esac

cat <<EOS

=========================================================================
 Bootstrap complete — harness is ready at $ROOT

 Restart Claude Code from dev/ so project-scope CLAUDE.md, settings.json,
 and hooks load:

   exit
   cd $ROOT/dev && claude

 Then in the new session:

   direnv allow
   nix develop --command $PM_INSTALL
   nix develop --command $PM_EXEC husky
   nix develop --command $PM_EXEC vitest run

 After tests are green:

   git remote add origin git@github.com:<owner>/<repo>.git
   git push --all origin
   bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
   bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>

 Then run /harness-team-lead.

 Architecture: ${ARCHITECTURE:-client-server}
 Package manager: $PM
 Codex: ${USE_CODEX:-no} (engineer=$USE_CODEX_ENGINEER e2e=$USE_CODEX_E2E_REVIEWER reviewer=$USE_CODEX_REVIEWER)
=========================================================================
EOS
