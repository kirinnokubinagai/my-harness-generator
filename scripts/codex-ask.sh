#!/usr/bin/env bash
# Summary: Bridge script that sends questions from Claude to Codex and receives the response.
#          Calls `codex exec` directly without depending on OMC or other external plugins.
#          When --session KEY is specified, Codex maintains a session for true multi-turn dialogue.
#
#          Image generation, model selection, etc. are Codex features — Claude simply asks
#          "Please save the logo to <path>" in normal conversation. This bridge does nothing extra.
#
# Usage:
#   codex-ask.sh "prompt"                                      # one-shot (no session)
#   codex-ask.sh --session brainstorm "..."                    # maintain session (new on first call, resume thereafter)
#   codex-ask.sh --session brainstorm --reset-session          # discard session
#   codex-ask.sh --role architect "..."                        # role prefix
#   codex-ask.sh --context f1 f2 -- "..."                     # attach context files
#   codex-ask.sh --out reply.md "..."                         # save result to file
#   codex-ask.sh --log session.jsonl --session brainstorm "..." # save all JSONL events
#   codex-ask.sh --set-active <project-root>                  # register active session pointer
#   codex-ask.sh --clear-active                               # discard active pointer
#
# Roles (--role):
#   architect / critic / analyst / planner / code-reviewer / security-reviewer / designer / tdd
#   engineer / e2e-reviewer / harness-reviewer  <- for delegation from harness subagents
#
# Session id contract (for harness subagents):
#   Each harness subagent (analyst / engineer / e2e-reviewer / reviewer) is responsible for
#   generating its own SESSION_ID at startup:
#
#     SPAWN_ID="$(date +%s)-$$"
#     SESSION_ID="<role>-<issue#>-<lane#>-${SPAWN_ID}"
#
#   The subagent passes --session "$SESSION_ID" on every call within its lifetime so that
#   Codex accumulates conversation context across turns (multi-turn dialog within one spawn).
#
#   This script does NOT invent or rewrite session ids. It uses whatever key is passed via
#   --session verbatim as the file-based session key (SESSION_KEY). The actual Codex session id
#   (SESSION_ID in the JSONL) is extracted from the first response and stored in
#   $SESSION_DIR/$SESSION_KEY.id for subsequent resume calls.
#
#   Fresh spawn = fresh SESSION_ID passed by the subagent = new .id file = new Codex session.
#   Auth-rescue resume = subagent passes the paused session's SESSION_ID = same .id file reused.

set -euo pipefail

# ===== Defaults =====
ROLE=""
MODEL=""        # Empty by default (defer to Codex CLI default model)
SANDBOX=""      # Empty by default (defer to Codex CLI default sandbox setting)
CONTEXT_FILES=()
OUT_FILE=""
LOG_FILE=""
SESSION_KEY=""
SESSION_DIR="${CODEX_SESSION_DIR:-./.codex-sessions}"
RESET_SESSION=0
SET_ACTIVE_PROJECT=""
CLEAR_ACTIVE=0
ACTIVE_POINTER="${CODEX_ACTIVE_POINTER:-$HOME/.codex-active-session}"

# ===== Argument parsing =====
PARSE_CONTEXT=0
while [[ $# -gt 0 ]]; do
  if [ "$PARSE_CONTEXT" -eq 1 ]; then
    if [ "$1" = "--" ]; then PARSE_CONTEXT=0; shift; continue; fi
    CONTEXT_FILES+=("$1"); shift; continue
  fi
  case "$1" in
    --role)            ROLE="$2";          shift 2 ;;
    --model)           MODEL="$2";         shift 2 ;;
    --sandbox)         SANDBOX="$2";       shift 2 ;;
    --context)         PARSE_CONTEXT=1;    shift ;;
    --out)             OUT_FILE="$2";      shift 2 ;;
    --log)             LOG_FILE="$2";      shift 2 ;;
    --session)         SESSION_KEY="$2";   shift 2 ;;
    --session-dir)     SESSION_DIR="$2";   shift 2 ;;
    --reset-session)   RESET_SESSION=1;    shift ;;
    --set-active)      SET_ACTIVE_PROJECT="$2"; shift 2 ;;
    --clear-active)    CLEAR_ACTIVE=1;     shift ;;
    --help|-h)
      sed -n '1,/^set -euo pipefail/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    --) shift; break ;;
    *) break ;;
  esac
done

# ===== --set-active / --clear-active standalone (no Codex CLI needed, pure file ops) =====
if [ "$CLEAR_ACTIVE" -eq 1 ]; then
  rm -f "$ACTIVE_POINTER"
  echo "[codex-ask] active session pointer discarded: $ACTIVE_POINTER" >&2
  exit 0
fi
if [ -n "$SET_ACTIVE_PROJECT" ]; then
  ABS_PATH=$(cd "$SET_ACTIVE_PROJECT" 2>/dev/null && pwd) || {
    echo "::error:: --set-active path does not exist: $SET_ACTIVE_PROJECT" >&2
    exit 1
  }
  if [ ! -f "$ABS_PATH/.my-harness/.config" ]; then
    echo "::error:: $ABS_PATH/.my-harness/.config not found (did you run bootstrap first?)" >&2
    exit 1
  fi
  printf '%s\n' "$ABS_PATH" > "$ACTIVE_POINTER"
  echo "[codex-ask] active session set: $ABS_PATH" >&2
  exit 0
fi

# ===== Auto-resolve session =====
#       Priority:
#       (1) --session is explicit → use it
#       (2) project's .my-harness/.config referenced by ~/.codex-active-session (global pointer)
#       (3) .my-harness/.config in cwd (or a parent directory)
load_config_from() {
  local project_root="$1"
  local cfg="$project_root/.my-harness/.config"
  [ -f "$cfg" ] || return 1
  local cfg_session
  cfg_session=$(grep -E "^CODEX_SESSION=" "$cfg" 2>/dev/null | head -1 | cut -d= -f2-)
  [ -n "$cfg_session" ] || return 1
  if [ -z "$SESSION_KEY" ]; then
    SESSION_KEY="$cfg_session"
  fi
  if [ "$SESSION_DIR" = "./.codex-sessions" ]; then
    SESSION_DIR="$project_root/.my-harness/codex-sessions"
  fi
  return 0
}

auto_resolve_session() {
  if [ -n "$SESSION_KEY" ]; then return 0; fi
  if [ -f "$ACTIVE_POINTER" ]; then
    local active_root
    active_root=$(head -1 "$ACTIVE_POINTER" 2>/dev/null)
    if [ -n "$active_root" ] && load_config_from "$active_root"; then
      echo "[codex-ask] session auto-resolved from active pointer: $SESSION_KEY (project: $active_root)" >&2
      return 0
    fi
  fi
  local current_dir="$PWD"
  while [ "$current_dir" != "/" ] && [ -n "$current_dir" ]; do
    if load_config_from "$current_dir"; then
      echo "[codex-ask] session auto-resolved from cwd: $SESSION_KEY (project: $current_dir)" >&2
      return 0
    fi
    current_dir=$(dirname "$current_dir")
  done
}
auto_resolve_session

# ===== --reset-session standalone =====
if [ "$RESET_SESSION" -eq 1 ]; then
  if [ -z "$SESSION_KEY" ]; then
    echo "::error:: --reset-session requires --session KEY (or .my-harness/.config)" >&2
    exit 1
  fi
  rm -f "$SESSION_DIR/$SESSION_KEY.id"
  echo "[codex-ask] session '$SESSION_KEY' discarded" >&2
  exit 0
fi

# ===== Check Codex CLI exists =====
if ! command -v codex >/dev/null 2>&1; then
  echo "::error:: codex CLI not found. Install with: npm i -g @openai/codex" >&2
  exit 127
fi

# ===== Capture ACTIVE_ROOT (for locating rescue state save destination) =====
ACTIVE_ROOT=""
if [ -f "$ACTIVE_POINTER" ]; then
  ACTIVE_ROOT=$(head -1 "$ACTIVE_POINTER" 2>/dev/null)
fi

# ===== Save Codex auth error rescue state =====
#       On auth expiry, save current request (session / role / prompt / context) as
#       JSON + .prompt.txt under `<root>/.my-harness/codex-auth-rescue/` so that
#       team-lead can resume the same session after `codex login`.
save_codex_auth_rescue() {
  local reason="$1"
  if [ -z "$ACTIVE_ROOT" ] || [ ! -d "$ACTIVE_ROOT/.my-harness" ]; then
    echo "::warning:: rescue state destination unknown (--set-active not called?)" >&2
    return
  fi
  local rescue_dir="$ACTIVE_ROOT/.my-harness/codex-auth-rescue"
  mkdir -p "$rescue_dir"
  local stamp
  stamp=$(date -u +%Y%m%dT%H%M%SZ)-$$
  local rescue_json="$rescue_dir/$stamp.json"
  local rescue_prompt="$rescue_dir/$stamp.prompt.txt"
  if [ -f "$TMP_PROMPT" ]; then
    cp "$TMP_PROMPT" "$rescue_prompt" 2>/dev/null || rescue_prompt=""
  else
    rescue_prompt=""
  fi
  # JSON contains metadata only (prompt body is in a separate file).
  # Shape (consumed by harness-team-lead resume protocol):
  # {
  #   "role":        the --role passed to this call (e.g. "engineer")
  #   "issue":       extracted from SESSION_KEY pattern "<role>-<issue#>-<lane#>-<spawn>" (or empty)
  #   "lane":        extracted from SESSION_KEY (or empty)
  #   "session_id":  the full SESSION_KEY passed as --session (subagent's composite id)
  #   "reason":      preflight-not-logged-in | preflight-not-installed | login-expired | subscription-or-quota
  #   "paused_at":   ISO 8601 UTC timestamp
  #   "next_action": human instructions for resuming
  #   "session_key": same as session_id (legacy field kept for backward compat)
  #   "out_file":    the --out file path (if any)
  #   "log_file":    the --log file path (if any)
  #   "prompt_path": path to the saved prompt text file
  # }
  local _issue="" _lane=""
  if [ -n "${SESSION_KEY:-}" ]; then
    # SESSION_KEY format: <role>-<issue#>-<lane#>-<epoch>-<pid>
    _issue=$(echo "$SESSION_KEY" | grep -oE '\-([0-9]+)\-' | head -1 | tr -d '-')
    _lane=$(echo  "$SESSION_KEY" | grep -oE '\-([0-9]+)\-' | sed -n '2p' | tr -d '-')
  fi
  {
    echo '{'
    echo "  \"role\": \"${ROLE:-}\","
    echo "  \"issue\": \"${_issue}\","
    echo "  \"lane\": \"${_lane}\","
    echo "  \"session_id\": \"${SESSION_KEY:-}\","
    echo "  \"reason\": \"$reason\","
    echo "  \"paused_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"next_action\": \"user runs \`codex login\` (or sets OPENAI_API_KEY), then says \`resume\` to harness-team-lead\","
    echo "  \"session_key\": \"${SESSION_KEY:-}\","
    echo "  \"out_file\": \"${OUT_FILE:-}\","
    echo "  \"log_file\": \"${LOG_FILE:-}\","
    echo "  \"prompt_path\": \"$rescue_prompt\""
    echo '}'
  } > "$rescue_json"
  echo "::error:: Codex auth error ($reason). Rescue state saved:" >&2
  echo "  $rescue_json" >&2
  echo "  Run \`codex login\` then tell team-lead to resume." >&2
}

# ===== Pre-flight auth check =====
#       Before calling codex exec, verify OAuth state with check-codex-auth.sh.
#       If not-logged-in, save rescue state and exit 100.
CHECK_AUTH="${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/check-codex-auth.sh"
if [ -x "$CHECK_AUTH" ]; then
  AUTH_STATE=$("$CHECK_AUTH" 2>/dev/null || true)
  if [ "$AUTH_STATE" != "logged-in" ]; then
    : "${TMP_PROMPT:=}"  # pre-define variable referenced by rescue function (empty content is fine)
    save_codex_auth_rescue "preflight-$AUTH_STATE"
    exit 100
  fi
fi

# ===== Build prompt =====
TMP_PROMPT=$(mktemp)
TMP_LOG=$(mktemp)
trap 'rm -f "$TMP_PROMPT" "$TMP_LOG"' EXIT

if [ ! -t 0 ]; then
  cat > "$TMP_PROMPT"
elif [ $# -gt 0 ]; then
  printf '%s\n' "$*" > "$TMP_PROMPT"
else
  echo "::error:: No prompt provided (pass as argument or via stdin)" >&2
  exit 1
fi

# ===== Role prefix =====
add_role_prefix() {
  local role="$1"
  local prefix=""
  case "$role" in
    architect)         prefix="You are a system architect. Answer from the perspective of design validity, tradeoffs, long-term maintainability, dependency direction, and boundary decisions." ;;
    critic)            prefix="You are a critical reviewer. Question assumptions, point out oversights and errors, and propose alternatives." ;;
    analyst)           prefix="You are a requirements analyst. Extract ambiguities, contradictions, and missing acceptance criteria, then ask clarifying questions." ;;
    planner)           prefix="You are a project planner. Organize executable ordering, dependencies, risks, and milestones." ;;
    code-reviewer)     prefix="You are a code reviewer. Point out bugs, performance issues, maintainability problems, naming issues, and gaps in test coverage." ;;
    security-reviewer) prefix="You are a security reviewer. Assess from the perspective of OWASP Top 10, authentication/authorization, input validation, secret management, and auditing." ;;
    designer)          prefix="You are a UI/UX designer. Think from the perspective of color, typography, information architecture, accessibility, and usability.

**Rules for image generation requests (logos / UI mocks / OG images / favicons — strictly enforced)**:
- Always use the built-in \`image_gen\` tool (gpt-image-2, official \$imagegen skill) to **generate PNG files directly**.
- The following alternatives are **absolutely prohibited**:
  - Writing HTML/CSS and screenshotting with Playwright/Puppeteer
  - Writing SVG paths and converting to PNG
  - Rasterizing with the \`<canvas>\` API
  - ASCII art / markdown pseudo-mocks
  - Any approach that involves writing code
- Output format: PNG only (transparent background is allowed). Use the resolution and save path specified by the requester.
- When multiple concepts or screens are needed, **call image_gen separately for each asset/variant** (do not batch with the \`n\` parameter).
- After generation, confirm the PNG exists at the requested save path and report the filename and path." ;;
    tdd)               prefix="You are a TDD coach. Ensure the test-first, minimal-implementation, refactor order is maintained." ;;
    engineer)          prefix="You are a TypeScript/Hono engineer working in the harness. Implement strictly following these rules: (1) TDD: write a failing test first, confirm red, then write minimal implementation. (2) Hono Clean Architecture: enforce the dependency direction domain ← application ← infrastructure / interfaces. (3) Nix pure: run all tools via \`nix develop --command\`. Impure commands like \`brew install\` are prohibited. (4) JSDoc/TSDoc required on all exports; inline comments inside function bodies are prohibited; descriptions in \$LANG. (5) Drizzle migrate-only: \`drizzle-kit push\` is absolutely prohibited; always use \`drizzle-kit generate --name <descriptive>\` then \`migrate\`. (6) Follow Biome conventions. (7) Resolve conflicts with merge commits only; rebase / reset --hard / push --force are prohibited." ;;
    e2e-reviewer)      prefix="You are an E2E test reviewer. Validate user flows using Playwright (Web) or Maestro (Mobile) and report results in a structured format: (1) Impact assessment: does the change affect E2E (yes/no). (2) Execution results: pass/fail for each test case. (3) On failure: specific reproduction steps and screenshot save paths. (4) Recommended action: pass → merge-ready, fail → specific fix proposal. Perform real-device-equivalent validation, not AI-style mock assertions." ;;
    harness-reviewer)  prefix="You are a harness convention reviewer. Scrutinize code changes from the following perspectives and flag violations at the file:line level: (1) Naming conventions: camelCase variables/functions, PascalCase types/classes, UPPER_SNAKE_CASE constants, kebab-case files. (2) JSDoc/TSDoc present on all exports. (3) No inline comments inside function bodies. (4) Hono Clean Architecture dependency direction. (5) Nix pure (no impure commands). (6) Lucide Icons only (emojis and other icon libraries prohibited). (7) Drizzle migrate-only. (8) Zod validation (API/form inputs). (9) WCAG AA compliance (color contrast, aria-label). (10) No any types, else statements, console.log, or hardcoded secrets. Output \`PASS\` explicitly if there are zero violations." ;;
    "") return 0 ;;
    *) prefix="You are $role. Answer according to your role." ;;
  esac
  local NEW
  NEW=$(mktemp)
  { echo "# Role"; echo "$prefix"; echo; echo "# Question"; cat "$TMP_PROMPT"; } > "$NEW"
  mv "$NEW" "$TMP_PROMPT"
}
add_role_prefix "$ROLE"

# ===== Append context files =====
if [ "${#CONTEXT_FILES[@]}" -gt 0 ]; then
  {
    echo
    echo "# Reference files"
    for f in "${CONTEXT_FILES[@]}"; do
      [ -f "$f" ] || { echo "::warning:: $f not found" >&2; continue; }
      echo
      echo "## $f"
      echo '```'
      cat "$f"
      echo '```'
    done
  } >> "$TMP_PROMPT"
fi

# ===== Extract only the final assistant message from JSONL =====
extract_assistant_text() {
  local jsonl="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r 'select(.type=="agent_message" or .type=="message" or .type=="assistant_message") | .content // .message // empty' "$jsonl" 2>/dev/null \
      | grep -v '^$' | tail -1
  else
    grep -oE '"content":"[^"]*"' "$jsonl" | tail -1 | sed 's/"content":"//; s/"$//'
  fi
}

# ===== Extract session_id from JSONL =====
extract_session_id() {
  local jsonl="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r 'select(.session_id) | .session_id' "$jsonl" 2>/dev/null | head -1
  else
    grep -oE '"session_id":"[^"]+"' "$jsonl" | head -1 | sed 's/"session_id":"//; s/"$//'
  fi
}

# ===== Common flags for Codex execution =====
#       --model / --sandbox are only added when explicitly specified by the user
COMMON_FLAGS=(--json)
[ -n "$MODEL" ]   && COMMON_FLAGS+=(--model "$MODEL")
[ -n "$SANDBOX" ] && COMMON_FLAGS+=(--sandbox "$SANDBOX")

# ===== Execute Codex =====
PROMPT_TEXT=$(cat "$TMP_PROMPT")

if [ -n "$SESSION_KEY" ]; then
  mkdir -p "$SESSION_DIR"
  SESSION_FILE="$SESSION_DIR/$SESSION_KEY.id"

  if [ -f "$SESSION_FILE" ]; then
    SESSION_ID=$(cat "$SESSION_FILE")
    echo "[codex-ask] resuming session '$SESSION_KEY' (id=$SESSION_ID)" >&2
    # codex CLI syntax: `codex exec resume [OPTIONS] [SESSION_ID] [PROMPT]`
    # Options must come before positional args to avoid misinterpretation by clap
    codex exec resume "${COMMON_FLAGS[@]}" "$SESSION_ID" "$PROMPT_TEXT" \
      2>"$TMP_LOG.err" | tee "$TMP_LOG" >/dev/null
  else
    echo "[codex-ask] creating new session '$SESSION_KEY'" >&2
    codex exec "${COMMON_FLAGS[@]}" "$PROMPT_TEXT" \
      2>"$TMP_LOG.err" | tee "$TMP_LOG" >/dev/null
    NEW_ID=$(extract_session_id "$TMP_LOG")
    if [ -z "$NEW_ID" ]; then
      # Fallback: get ID from most recent jsonl filename under ~/.codex/sessions
      NEW_ID=$(find "${HOME}/.codex/sessions" -name "*.jsonl" -mmin -1 2>/dev/null \
        | xargs -I{} basename {} .jsonl 2>/dev/null | head -1)
    fi
    if [ -n "$NEW_ID" ]; then
      echo "$NEW_ID" > "$SESSION_FILE"
      echo "[codex-ask] session id saved to $SESSION_FILE" >&2
    else
      echo "::warning:: Could not obtain session ID. Next call will start a new session." >&2
    fi
  fi
else
  codex exec "${COMMON_FLAGS[@]}" "$PROMPT_TEXT" \
    2>"$TMP_LOG.err" | tee "$TMP_LOG" >/dev/null
fi

# ===== Post-exec auth / subscription error detection =====
#       Distinguish two failure types that can occur during execution:
#       (a) login-expired    : OAuth token invalid/expired → fix with `codex login`
#       (b) subscription-or-quota : subscription expired / quota exceeded / billing → separate action required
if [ -f "$TMP_LOG.err" ]; then
  # Check subscription / quota / billing first (higher priority than login errors, prevents misclassification)
  if grep -iE "subscription.*(expired|required|cancel|inactive)|no active subscription|plan.*(required|expired|inactive)|quota.*(exceeded|reached)|billing.*(required|issue|past due|invalid)|insufficient.*(quota|credit|funds)|payment.*required|usage.*limit.*(exceeded|reached)" \
       "$TMP_LOG.err" >/dev/null 2>&1; then
    save_codex_auth_rescue "subscription-or-quota"
    exit 100
  fi
  # Then check login / auth token issues
  if grep -iE "not logged in|please log in|please run.*codex login|authentication failed|api key.*(required|missing|invalid)|unauthorized|401 [^0-9]|expired.*(token|session|credential)|invalid_grant|oauth.*(failed|invalid)" \
       "$TMP_LOG.err" >/dev/null 2>&1; then
    save_codex_auth_rescue "login-expired"
    exit 100
  fi
fi

# ===== Save log =====
if [ -n "$LOG_FILE" ]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  cp "$TMP_LOG" "$LOG_FILE"
  echo "[codex-ask] JSONL log saved to $LOG_FILE" >&2
fi

# ===== Output only the assistant body to stdout =====
ASSISTANT_TEXT=$(extract_assistant_text "$TMP_LOG")

if [ -z "$ASSISTANT_TEXT" ]; then
  echo "::warning:: Could not extract assistant body. Use --log to save JSONL for inspection." >&2
  cat "$TMP_LOG" >&2
  exit 1
fi

if [ -n "$OUT_FILE" ]; then
  mkdir -p "$(dirname "$OUT_FILE")"
  printf '%s\n' "$ASSISTANT_TEXT" > "$OUT_FILE"
  echo "[codex-ask] response saved to $OUT_FILE" >&2
else
  printf '%s\n' "$ASSISTANT_TEXT"
fi
