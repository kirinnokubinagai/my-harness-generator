#!/usr/bin/env bash
# 概要: ハーネス用の Claude 設定を整備する。
#       常に行うこと:
#         - ~/.claude/skills/harness-* をハーネステンプレから上書きインストール
#         - ~/.claude/agents/harness-* も同様（既存はそのまま、無いものだけ追加）
#         - ~/.claude/settings.json にユーザー入力ログ用フックを **マージ** 登録
#       USE_GLOBAL_CLAUDE=no のとき追加で行うこと:
#         - dev/.claude/CLAUDE.md にハーネス専用の薄い指示を配置
#         - dev/.claude/settings.json にも hook を登録
#         - dev/.claude/skills/, dev/.claude/agents/ にコピー（独立配置）

set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"

if [ -f "$ROOT/.my-harness/.config" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/.my-harness/.config"
fi
USE_GLOBAL_CLAUDE="${USE_GLOBAL_CLAUDE:-yes}"

# ===== 共通: ハーネス skills / agents をインストール =====
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
  echo "  → $target_dir に $installed 個の harness-* skill"
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
  echo "  → $target_dir に $installed 個の harness-* agent"
}

# settings.json に hook をマージ登録（既存設定は破壊しない）
merge_hook_into_settings() {
  local settings_path="$1"
  mkdir -p "$(dirname "$settings_path")"
  [ -f "$settings_path" ] || echo '{}' > "$settings_path"
  if ! command -v jq >/dev/null 2>&1; then
    echo "  ::warning:: jq が無いため $settings_path に手動追記してください: hooks.UserPromptSubmit / Stop"
    return 0
  fi
  local user_prompt_hook="bash $HARNESS_DIR/templates/hooks/log-user-prompt.sh"
  local stop_hook="bash $HARNESS_DIR/templates/hooks/log-claude-output.sh"
  local tmp
  tmp=$(mktemp)
  jq \
    --arg up "$user_prompt_hook" \
    --arg sp "$stop_hook" \
    '
    .hooks //= {} |
    .hooks.UserPromptSubmit //= [] |
    .hooks.Stop //= [] |
    if any(.hooks.UserPromptSubmit[]; .command == $up) then . else .hooks.UserPromptSubmit += [{"command": $up}] end |
    if any(.hooks.Stop[]; .command == $sp) then . else .hooks.Stop += [{"command": $sp}] end
    ' "$settings_path" > "$tmp" && mv "$tmp" "$settings_path"
  echo "  → $settings_path に hook を登録"
}

# ===== 1. グローバルに skills + hooks をインストール（USE_GLOBAL_CLAUDE 不問）=====
echo "[setup-claude] グローバル ~/.claude/skills/ に harness-* skills をインストール"
install_harness_skills_into "$HOME/.claude/skills"

echo "[setup-claude] グローバル ~/.claude/settings.json に hook を登録"
merge_hook_into_settings "$HOME/.claude/settings.json"

# ===== 2. USE_GLOBAL_CLAUDE=yes ならここまで =====
if [ "$USE_GLOBAL_CLAUDE" = "yes" ]; then
  echo "[setup-claude] グローバル設定を引き継ぎます（dev/.claude/ への独立配置はスキップ）"
  cat <<EOS

==== Claude Code 再起動が必要 ====
新しい harness-* skill と hooks を有効にするため、
Claude Code を再起動するか、現在のセッションで /clear を実行してください。
==================================
EOS
  exit 0
fi

# ===== 3. USE_GLOBAL_CLAUDE=no: dev/.claude/ に独立配置 =====
DEST="$ROOT/dev/.claude"
mkdir -p "$DEST/skills" "$DEST/agents"

# 薄い CLAUDE.md（skill 中心の指示）
if [ ! -f "$DEST/CLAUDE.md" ]; then
  cp "$HARNESS_DIR/templates/claude/CLAUDE.thin.md" "$DEST/CLAUDE.md"
  echo "[setup-claude] dev/.claude/CLAUDE.md（薄い skill 指向版）を配置"
fi

# settings.json: hook をプロジェクトローカルにも登録（global と独立に動かしたい場合）
[ -f "$DEST/settings.json" ] || echo '{}' > "$DEST/settings.json"
merge_hook_into_settings "$DEST/settings.json"

# skills / agents コピー
install_harness_skills_into "$DEST/skills"
install_harness_agents_into "$DEST/agents"

# my-harness-init の skill もプロジェクトに同梱しておく（オフラインでも /my-harness-init が使える）
if [ -d "$HOME/.claude/skills/my-harness-init" ]; then
  mkdir -p "$DEST/skills/my-harness-init"
  cp "$HOME/.claude/skills/my-harness-init/SKILL.md" "$DEST/skills/my-harness-init/SKILL.md" 2>/dev/null || true
fi

cat <<EOS

[setup-claude] 完了。
  - グローバル ~/.claude/skills/ に harness-* と各種 hook 登録済み
  - プロジェクト独立配置: $DEST 配下に CLAUDE.md / skills / agents / settings.json
  - 個人の ~/.claude/* も Claude Code 仕様上マージされる点に注意

==== Claude Code 再起動が必要 ====
新しい dev/.claude/CLAUDE.md と skills / hooks を完全に有効化するため、
Claude Code を再起動するか /clear を実行してください。
==================================
EOS
