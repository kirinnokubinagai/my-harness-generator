#!/usr/bin/env bash
# Verifies CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 is set, either in
# ~/.claude/settings.json (env block) or as an exported environment variable.
# Exits 0 when enabled, 1 with a remediation message otherwise.

set -u

CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

if grep -q "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" "$CLAUDE_SETTINGS" 2>/dev/null; then
  exit 0
fi

if [ -n "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
  exit 0
fi

cat >&2 <<EOF
::error:: Agent Teams is not enabled.
         Add to $CLAUDE_SETTINGS:
           "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" }
         Then restart Claude Code and re-run /harness-team-lead.
EOF
exit 1
