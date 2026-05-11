#!/usr/bin/env bash
# codex-exec.sh — run `codex exec` against a lane worktree.
#
# Unlike codex-ask.sh (single-turn Q&A returning text), this wrapper lets Codex
# perform real file edits inside the worktree (sandbox=workspace-write) or read
# the worktree freely for review (sandbox=read-only). Used by:
#   - engineer-N when USE_CODEX_ENGINEER=yes  → workspace-write
#   - reviewer-N when USE_CODEX_REVIEWER=yes  → read-only
#
# Codex auto-discovers AGENTS.md / CLAUDE.md by walking the worktree, so the
# rule body lives in those files (bootstrap.sh generates them from
# templates/CLAUDE.md.tmpl, pointing at .my-harness/rules/*.md). We do NOT
# re-attach rules here — that would double the context.
#
# Exit codes:
#   0    success
#   100  codex auth failure (subscription expired / not logged in)
#   *    codex exec exit code passed through
#
# Usage:
#   codex-exec.sh --role <engineer|harness-reviewer> \
#                 --worktree <path> \
#                 [--session <id>] \
#                 [--readonly] \
#                 [--out <log path>] \
#                 [--timeout <minutes>] \
#                 "<task description>"

set -u

ROLE=""
WORKTREE=""
SESSION=""
OUT=""
READONLY=no
TIMEOUT_MIN=30
TASK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --role)      ROLE="$2";          shift 2 ;;
    --worktree)  WORKTREE="$2";      shift 2 ;;
    --session)   SESSION="$2";       shift 2 ;;
    --out)       OUT="$2";           shift 2 ;;
    --readonly)  READONLY=yes;       shift 1 ;;
    --timeout)   TIMEOUT_MIN="$2";   shift 2 ;;
    --)          shift; TASK="$*"; break ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# *//'
      exit 0
      ;;
    *)           TASK="$1";          shift 1 ;;
  esac
done

if [ -z "$ROLE" ] || [ -z "$WORKTREE" ] || [ -z "$TASK" ]; then
  echo "::error:: codex-exec.sh requires --role, --worktree, and a task" >&2
  echo "         usage: codex-exec.sh --role <engineer|harness-reviewer> --worktree <path> [--session <id>] [--readonly] [--out <log>] \"<task>\"" >&2
  exit 64
fi

if [ ! -d "$WORKTREE" ]; then
  echo "::error:: codex-exec.sh: worktree not found: $WORKTREE" >&2
  exit 65
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "::error:: codex-exec.sh: 'codex' CLI not in PATH. Install: npm install -g @openai/codex" >&2
  exit 66
fi

# ===== Role prefix =====
# Short pointer only — the actual rules live in AGENTS.md / CLAUDE.md inside
# the worktree, which Codex auto-discovers.
case "$ROLE" in
  engineer)
    PREFIX="You are a TypeScript/Hono engineer working in this harness worktree. Follow every rule in AGENTS.md (or CLAUDE.md) and the files it references under .my-harness/rules/. Modify files in this worktree to satisfy the task below. NEVER touch git — the orchestrator's analyst owns all git operations."
    ;;
  harness-reviewer)
    PREFIX="You are a harness convention reviewer. Use AGENTS.md (or CLAUDE.md) and the rule files under .my-harness/rules/ as the checklist. Read whatever you need from the worktree. Output \`PASS\` if there are zero violations, otherwise emit file:line violations and concrete fix suggestions. Do NOT modify any files."
    ;;
  *)
    echo "::error:: codex-exec.sh: unknown role '$ROLE' (expected: engineer | harness-reviewer)" >&2
    exit 65
    ;;
esac

# ===== Sandbox =====
if [ "$READONLY" = "yes" ] || [ "$ROLE" = "harness-reviewer" ]; then
  SANDBOX="read-only"
else
  SANDBOX="workspace-write"
fi

# ===== Build the full prompt =====
FULL_PROMPT="# Role
$PREFIX

# Task
$TASK"

# ===== Optional --out tee =====
TEE_TARGET=""
if [ -n "$OUT" ]; then
  mkdir -p "$(dirname "$OUT")" 2>/dev/null
  TEE_TARGET="$OUT"
fi

# ===== Session resume vs new =====
RESUME_ARGS=()
if [ -n "$SESSION" ]; then
  # codex exec resume <session-id> for follow-up turns. The first call uses
  # `codex exec`, subsequent FIX turns within the same issue can pass the same
  # session id — codex will resume if it exists, otherwise start fresh.
  RESUME_ARGS=(resume "--last")
  # NOTE: codex 0.130+ stores sessions by uuid, not arbitrary names. We rely on
  # --last instead of --session for now; if the user needs strict resume by id
  # we revisit when codex exposes that.
fi

# ===== Run codex exec =====
TIMEOUT_SEC=$(( TIMEOUT_MIN * 60 ))

# stderr → progress (preserved), stdout → final agent_message
# --ask-for-approval never (mandatory in non-interactive mode)
# --cd <worktree> so Codex's cwd matches the lane
CODEX_CMD=(
  codex exec
  --cd "$WORKTREE"
  --sandbox "$SANDBOX"
  --ask-for-approval never
)

if command -v timeout >/dev/null 2>&1; then
  RUN=(timeout "${TIMEOUT_SEC}s" "${CODEX_CMD[@]}")
else
  RUN=("${CODEX_CMD[@]}")
fi

if [ -n "$TEE_TARGET" ]; then
  printf '%s\n' "$FULL_PROMPT" | "${RUN[@]}" 2> >(tee -a "$TEE_TARGET.stderr" >&2) | tee "$TEE_TARGET"
  CODEX_RC=${PIPESTATUS[1]}
else
  printf '%s\n' "$FULL_PROMPT" | "${RUN[@]}"
  CODEX_RC=${PIPESTATUS[1]}
fi

# ===== Auth-failure detection =====
# codex prints auth errors to stderr in a recognisable shape. If we have a tee
# of stderr, inspect it.
if [ "$CODEX_RC" -ne 0 ] && [ -n "$TEE_TARGET" ] && [ -f "$TEE_TARGET.stderr" ]; then
  if grep -qiE "not (logged in|authenticated)|please run \`codex login\`|subscription (expired|required)|quota (exceeded|exhausted)" "$TEE_TARGET.stderr"; then
    exit 100
  fi
fi

exit "$CODEX_RC"
