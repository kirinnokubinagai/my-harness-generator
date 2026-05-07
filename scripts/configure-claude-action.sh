#!/usr/bin/env bash
# Summary: Switches the Claude Code Action authentication section based on bootstrap.env selections.
#          Uses only sed and awk (no Python or yaml dependency) for macOS/Linux compatibility.
#          If USE_CLAUDE_ACTION=no, removes the claude-review job from the workflow entirely.
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"
# shellcheck disable=SC1091
source "$ROOT/.my-harness/.config"
cd "$ROOT/dev"

WF=".github/workflows/pr-to-dev.yml"
[ -f "$WF" ] || { echo "[configure-claude-action] $WF not found, skipping"; exit 0; }

if [ "$USE_CLAUDE_ACTION" = "no" ]; then
  # Remove the entire claude-review: ... block.
  # Deletes up to the next job at the same indent level (2 spaces).
  awk '
    BEGIN { skip = 0 }
    /^  claude-review:/ { skip = 1; next }
    skip == 1 && /^  [A-Za-z0-9_-]+:/ { skip = 0 }
    skip == 0 { print }
  ' "$WF" > "$WF.tmp" && mv "$WF.tmp" "$WF"

  # Remove "claude-review" from auto-merge.needs
  # Assumes the form: `needs: [guard, quality, e2e, claude-review]`
  sed -i.bak -E 's/, *claude-review//; s/claude-review *, *//; s/\[claude-review\]/\[\]/' "$WF"
  rm -f "$WF.bak"

  echo "[configure-claude-action] claude-review job removed"
  exit 0
fi

# Set the auth type. The pr-to-dev.yml default is CLAUDE_CODE_OAUTH_TOKEN,
# so only substitute when api is chosen.
if [ "$CLAUDE_AUTH" = "api" ]; then
  sed -i.bak \
    -e 's|CLAUDE_CODE_OAUTH_TOKEN: \${{ secrets\.CLAUDE_CODE_OAUTH_TOKEN }}|ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}|' \
    "$WF"
  rm -f "$WF.bak"
  echo "[configure-claude-action] auth=api (ANTHROPIC_API_KEY) applied"
else
  echo "[configure-claude-action] auth=oauth (CLAUDE_CODE_OAUTH_TOKEN, default) applied"
fi
