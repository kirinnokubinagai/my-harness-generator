#!/usr/bin/env bash
# Summary: Sets up Claude configuration for the harness.
#          Always does:
#            - Installs harness-* skills from the harness template into ~/.claude/skills/ (overwrite)
#            - Installs harness-* agents similarly (adds missing ones, keeps existing)
#            - Merges the user input log hooks into ~/.claude/settings.json (non-destructive)
#          Additionally when USE_GLOBAL_CLAUDE=no:
#            - Places a thin harness-specific CLAUDE.md in dev/.claude/
#            - Registers hooks in dev/.claude/settings.json as well
#            - Copies skills and agents to dev/.claude/ (independent placement)

set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"

if [ -f "$ROOT/.my-harness/.config" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/.my-harness/.config"
fi
USE_GLOBAL_CLAUDE="${USE_GLOBAL_CLAUDE:-yes}"

# ===== Common: Install harness skills / agents =====
install_harness_skills_into() {
  local target_dir="$1"
  local installed=0
  mkdir -p "$target_dir"
  if [ -d "$HARNESS_DIR/templates/skills" ]; then
    for src_skill in "$HARNESS_DIR/templates/skills"/harness-*; do
      [ -d "$src_skill" ] || continue
      local skill_name
      skill_name=$(basename "$src_skill")
      mkdir -p "$target_dir/$skill_name"
      cp "$src_skill/SKILL.md" "$target_dir/$skill_name/SKILL.md"
      installed=$((installed + 1))
    done
  fi
  echo "  → $installed harness-* skill(s) installed to $target_dir"
}

install_harness_agents_into() {
  local target_dir="$1"
  local installed=0
  mkdir -p "$target_dir"
  if [ -d "$HOME/.claude/agents" ]; then
    for src_agent in "$HOME/.claude/agents"/harness-*.md; do
      [ -f "$src_agent" ] || continue
      cp "$src_agent" "$target_dir/$(basename "$src_agent")"
      installed=$((installed + 1))
    done
  fi
  echo "  → $installed harness-* agent(s) installed to $target_dir"
}

# Merge hooks into settings.json without destroying existing settings
merge_hook_into_settings() {
  local settings_path="$1"
  mkdir -p "$(dirname "$settings_path")"
  [ -f "$settings_path" ] || echo '{}' > "$settings_path"
  if ! command -v jq >/dev/null 2>&1; then
    echo "  ::warning:: jq not found — add hooks to $settings_path manually: hooks.UserPromptSubmit / Stop"
    return 0
  fi
  local user_prompt_hook="bash $HARNESS_DIR/hooks/log-user-prompt.sh"
  local stop_hook="bash $HARNESS_DIR/hooks/log-claude-output.sh"
  local tmp
  tmp=$(mktemp)
  jq \
    --arg up "$user_prompt_hook" \
    --arg sp "$stop_hook" \
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
    ' "$settings_path" > "$tmp" && mv "$tmp" "$settings_path"
  echo "  → hooks registered in $settings_path"
}

# ===== 1. Install skills + hooks globally (regardless of USE_GLOBAL_CLAUDE) =====
echo "[setup-claude] Installing harness-* skills to global ~/.claude/skills/"
install_harness_skills_into "$HOME/.claude/skills"

echo "[setup-claude] Registering hooks in global ~/.claude/settings.json"
merge_hook_into_settings "$HOME/.claude/settings.json"

# ===== 2. If USE_GLOBAL_CLAUDE=yes, stop here =====
if [ "$USE_GLOBAL_CLAUDE" = "yes" ]; then
  echo "[setup-claude] Inheriting global settings (skipping independent placement in dev/.claude/)"
  cat <<EOS

==== Claude Code restart required ====
To activate the new harness-* skills and hooks,
restart Claude Code or run /clear in the current session.
======================================
EOS
  exit 0
fi

# ===== 3. USE_GLOBAL_CLAUDE=no: place independently in dev/.claude/ =====
DEST="$ROOT/dev/.claude"
mkdir -p "$DEST/skills" "$DEST/agents"

# Thin CLAUDE.md (skill-oriented instructions)
if [ ! -f "$DEST/CLAUDE.md" ]; then
  cp "$HARNESS_DIR/templates/claude/CLAUDE.thin.md" "$DEST/CLAUDE.md"
  echo "[setup-claude] Placed dev/.claude/CLAUDE.md (thin skill-oriented version)"
fi

# Register hooks in project-local settings.json as well (independent of global)
[ -f "$DEST/settings.json" ] || echo '{}' > "$DEST/settings.json"
merge_hook_into_settings "$DEST/settings.json"

# Copy skills and agents
install_harness_skills_into "$DEST/skills"
install_harness_agents_into "$DEST/agents"

# Also bundle my-harness-init skill with the project (available offline)
if [ -d "$HOME/.claude/skills/my-harness-init" ]; then
  mkdir -p "$DEST/skills/my-harness-init"
  cp "$HOME/.claude/skills/my-harness-init/SKILL.md" "$DEST/skills/my-harness-init/SKILL.md" 2>/dev/null || true
fi

cat <<EOS

[setup-claude] Done.
  - Global ~/.claude/skills/ has harness-* skills and hooks registered
  - Independent project placement: CLAUDE.md / skills / agents / settings.json under $DEST
  - Note: Personal ~/.claude/* is also merged by Claude Code per its specification

==== Claude Code restart required ====
To fully activate the new dev/.claude/CLAUDE.md, skills, and hooks,
restart Claude Code or run /clear.
======================================
EOS
