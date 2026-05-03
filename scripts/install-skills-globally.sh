#!/usr/bin/env bash
# 概要: ローカルチェックアウトから直接 ~/.claude/skills/ にインストールする（plugin install しない場合の代替）。
#       推奨は: /plugin marketplace add <repo> + /plugin install my-harness-harness-generator
#       ~/.claude/ に直接インストールする（bootstrap を経由しない）。
#       既存ファイルは上書き（最新テンプレに同期）するので、ジェネレータ更新後の反映に使う。
#
# 使い方:
#   bash ${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/install-skills-globally.sh
#   bash ${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/install-skills-globally.sh --no-hooks   # hooks 登録をスキップ
#
# やること:
#   1. templates/skills/harness-* を ~/.claude/skills/ に上書きコピー
#   2. ~/.claude/settings.json に UserPromptSubmit / Stop hook を jq でマージ登録
#   3. 完了後は Claude Code を再起動するか /clear で再ロード

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
echo "  → $INSTALLED 個の harness-* skill を install"

# my-harness-init / my-harness-generator も同期（既存があれば上書き）
for top_skill in my-harness-init my-harness-generator; do
  if [ -f "$HARNESS_DIR/templates/skills/$top_skill/SKILL.md" ]; then
    mkdir -p "$CLAUDE_SKILLS_DIR/$top_skill"
    cp "$HARNESS_DIR/templates/skills/$top_skill/SKILL.md" "$CLAUDE_SKILLS_DIR/$top_skill/SKILL.md"
    echo "  → $top_skill を install/更新"
  fi
done

# hooks を ~/.claude/settings.json にマージ登録
if [ "$SKIP_HOOKS" -eq 0 ]; then
  SETTINGS="$HOME/.claude/settings.json"
  mkdir -p "$(dirname "$SETTINGS")"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  if ! command -v jq >/dev/null 2>&1; then
    echo "  ::warning:: jq が無いため hooks 登録をスキップ。手動で settings.json に追記してください。"
  else
    USER_HOOK="bash $HARNESS_DIR/templates/hooks/log-user-prompt.sh"
    STOP_HOOK="bash $HARNESS_DIR/templates/hooks/log-claude-output.sh"
    tmp=$(mktemp)
    jq \
      --arg up "$USER_HOOK" \
      --arg sp "$STOP_HOOK" \
      '
      .hooks //= {} |
      .hooks.UserPromptSubmit //= [] |
      .hooks.Stop //= [] |
      if any(.hooks.UserPromptSubmit[]; .command == $up) then . else .hooks.UserPromptSubmit += [{"command": $up}] end |
      if any(.hooks.Stop[]; .command == $sp) then . else .hooks.Stop += [{"command": $sp}] end
      ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  → ~/.claude/settings.json に UserPromptSubmit / Stop hook を登録"
  fi
fi

cat <<EOS

==== install-skills-globally 完了 ====
  install されたディレクトリ: $CLAUDE_SKILLS_DIR/harness-* と my-harness-init / my-harness-generator
  hooks 登録: ~/.claude/settings.json
  ※ Claude Code を再起動するか /clear を実行して反映してください
======================================
EOS
