#!/usr/bin/env bash
# guard-codex-direct.sh — Claude Code PreToolUse hook that detects and
# BLOCKS direct codex CLI invocations that bypass scripts/codex-ask.sh.
#
# Enforces HARD RULE 4 from skills/my-harness-init/SKILL.md.
#
# Install — add to ~/.claude/settings.json under "hooks":
#
#   "PreToolUse": [
#     {
#       "matcher": "Bash",
#       "hooks": [
#         { "type": "command", "command": "bash ~/my-harness-generator/hooks/guard-codex-direct.sh" }
#       ]
#     }
#   ]
#
# (If you have other PreToolUse hooks already, add this one alongside them.)
#
# Hook input (stdin): JSON with shape { "tool_input": { "command": "..." }, ... }
# Hook output behavior:
#   - exit 0     : allow the Bash tool call to proceed
#   - exit 2     : BLOCK the call; stderr is shown to Claude as the reason
#
# Escape hatch:
#   HARNESS_ALLOW_DIRECT_CODEX=yes (or =1) in the environment bypasses
#   this guard. Use only when debugging the harness itself.

set -u

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0   # No input → not our concern

# Try jq first, fall back to python for systems without jq
CMD=""
if command -v jq >/dev/null 2>&1; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
elif command -v python3 >/dev/null 2>&1; then
  CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null || true)
fi
[ -z "$CMD" ] && exit 0   # Could not parse — be permissive

# Detect direct `codex <subcommand>` invocations.
# Allowed when:
#   - The command pipes through scripts/codex-ask.sh
#   - HARNESS_ALLOW_DIRECT_CODEX is yes/1
#   - The command is just `codex --version` or `codex --help` (read-only probes)
case "${HARNESS_ALLOW_DIRECT_CODEX:-no}" in
  yes|1|true) exit 0 ;;
esac

if echo "$CMD" | grep -qE '(^|[;&|]|^[[:space:]]*)codex[[:space:]]+(exec|chat|run|app-server|message)' && \
   ! echo "$CMD" | grep -q 'codex-ask\.sh'; then
  cat >&2 <<EOF

::block:: Direct \`codex\` CLI invocation detected — BLOCKED.

Command that triggered the block:
  $CMD

This harness requires all Codex calls to flow through
\`scripts/codex-ask.sh\` (HARD RULE 4 in skills/my-harness-init/SKILL.md).
The wrapper provides reasoning-model guard, auth-error translation,
retry / refine integration, session management, and error logging.
Bypassing it loses every defensive layer.

Rewrite as:
  bash ~/my-harness-generator/scripts/codex-ask.sh "<your prompt>"

(adjust path if your harness install is elsewhere; cwd is auto-resolved
to the current project, session id is derived from the project slug
unless you pass --session <key>.)

If you have a LEGITIMATE reason to bypass (debugging the harness itself,
testing the codex-app-server protocol directly), prefix with:
  HARNESS_ALLOW_DIRECT_CODEX=yes <your codex command>

EOF
  exit 2   # Block the Bash tool call
fi

# Block Bash-level edits of ~/.codex/config.toml plugin flags (HARD RULE 5).
# (The Edit/Write tools are a separate matcher; this catches sed/tee/echo.)
if echo "$CMD" | grep -qE '(\.codex/config\.toml|CODEX_HOME.*config\.toml)' && \
   echo "$CMD" | grep -qE '(sed -i|>>|> |tee |dd of=)'; then
  cat >&2 <<'EOF'

::block:: Attempt to edit ~/.codex/config.toml via Bash — BLOCKED (HARD RULE 5).

Toggling Codex plugins by editing config.toml PERSISTS the change and
breaks Codex for every other use on this machine.

Use the per-call mechanism instead:
  bash ~/my-harness-generator/scripts/codex-ask.sh --disable-plugin "<plugin-id>" "<prompt>"

Or for a session-wide default without touching the file:
  export MY_HARNESS_CODEX_DISABLE_PLUGINS="<plugin-id>,<another>"

Escape hatch (debugging the harness itself):
  HARNESS_ALLOW_DIRECT_CODEX=yes <command>
EOF
  case "${HARNESS_ALLOW_DIRECT_CODEX:-no}" in yes|1|true) exit 0 ;; esac
  exit 2
fi

exit 0   # Allow everything else
