#!/usr/bin/env bash
# Summary: Installs directly from a local checkout to ~/.claude/skills/ (alternative to plugin install).
#          Recommended approach: /plugin marketplace add <repo> + /plugin install my-harness-harness-generator
#          Installs directly to ~/.claude/ (bypasses bootstrap).
#          Overwrites existing files (syncs to the latest template), so use this after generator updates.
#
# Usage:
#   bash ${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/install-skills-globally.sh
#   bash ${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/install-skills-globally.sh --no-hooks   # skip hook registration
#
# What it does:
#   1. Copies templates/skills/harness-* to ~/.claude/skills/ (overwrite)
#   2. Merges UserPromptSubmit / Stop hooks into ~/.claude/settings.json using jq
#   3. After completion, restart Claude Code or run /clear to apply changes

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKIP_HOOKS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-hooks) SKIP_HOOKS=1; shift ;;
    --help|-h) sed -n '1,/^set -euo pipefail/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) shift ;;
  esac
done

CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$CLAUDE_SKILLS_DIR"

echo "[install] templates/skills/ → ~/.claude/skills/"
INSTALLED=0
for src_skill in "$HARNESS_DIR/templates/skills"/harness-*; do
  [ -d "$src_skill" ] || continue
  skill_name=$(basename "$src_skill")
  mkdir -p "$CLAUDE_SKILLS_DIR/$skill_name"
  cp "$src_skill/SKILL.md" "$CLAUDE_SKILLS_DIR/$skill_name/SKILL.md"
  INSTALLED=$((INSTALLED + 1))
done
echo "  → $INSTALLED harness-* skill(s) installed"

# Also sync my-harness-init / my-harness-generator (overwrite if they exist)
for top_skill in my-harness-init my-harness-generator; do
  if [ -f "$HARNESS_DIR/templates/skills/$top_skill/SKILL.md" ]; then
    mkdir -p "$CLAUDE_SKILLS_DIR/$top_skill"
    cp "$HARNESS_DIR/templates/skills/$top_skill/SKILL.md" "$CLAUDE_SKILLS_DIR/$top_skill/SKILL.md"
    echo "  → $top_skill installed/updated"
  fi
done

# Merge hooks into ~/.claude/settings.json
if [ "$SKIP_HOOKS" -eq 0 ]; then
  SETTINGS="$HOME/.claude/settings.json"
  mkdir -p "$(dirname "$SETTINGS")"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  if ! command -v jq >/dev/null 2>&1; then
    echo "  ::warning:: jq not found — skipping hook registration. Add hooks to settings.json manually."
  else
    USER_HOOK="bash $HARNESS_DIR/hooks/log-user-prompt.sh"
    STOP_HOOK="bash $HARNESS_DIR/hooks/log-claude-output.sh"
    tmp=$(mktemp)
    jq \
      --arg up "$USER_HOOK" \
      --arg sp "$STOP_HOOK" \
      '
      def repair_legacy:
        map(
          if type == "object" and has("command") and (has("hooks") | not)
            then {"hooks": [{"type": "command", "command": .command}]}
            else .
          end
        );
      .hooks //= {} |
      .hooks.UserPromptSubmit //= [] |
      .hooks.Stop //= [] |
      .hooks.UserPromptSubmit |= repair_legacy |
      .hooks.Stop |= repair_legacy |
      if [.hooks.UserPromptSubmit[]?.hooks[]?.command] | index($up)
        then .
        else .hooks.UserPromptSubmit += [{"hooks": [{"type": "command", "command": $up}]}]
      end |
      if [.hooks.Stop[]?.hooks[]?.command] | index($sp)
        then .
        else .hooks.Stop += [{"hooks": [{"type": "command", "command": $sp}]}]
      end
      ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  → UserPromptSubmit / Stop hooks registered in ~/.claude/settings.json"
  fi
fi

cat <<EOS

==== install-skills-globally complete ====
  Installed to: $CLAUDE_SKILLS_DIR/harness-* and my-harness-init / my-harness-generator
  Hooks registered: ~/.claude/settings.json
  * Restart Claude Code or run /clear to apply changes
==========================================
EOS
