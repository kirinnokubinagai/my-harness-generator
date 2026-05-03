#!/usr/bin/env bash
# 概要: Claude グローバル設定の引き継ぎ / 独立配置を切り替える。
#       USE_GLOBAL_CLAUDE=yes: 何もしない（~/.claude/* がそのまま効く）
#       USE_GLOBAL_CLAUDE=no:
#         - dev/.claude/CLAUDE.md にハーネス専用 instructions を配置
#         - ~/.claude/skills/harness-* と ~/.claude/agents/harness-* を dev/.claude/ にコピー
#         - dev/.claude/settings.json に最小設定（hooks 等は引き継がない）
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"
# shellcheck disable=SC1091
source "$ROOT/.harness-init/.config" 2>/dev/null || \
  source "$ROOT/.harness/.bootstrap.env" 2>/dev/null || true

USE_GLOBAL_CLAUDE="${USE_GLOBAL_CLAUDE:-yes}"

if [ "$USE_GLOBAL_CLAUDE" = "yes" ]; then
  echo "[setup-claude] グローバル ~/.claude/* を引き継ぎます（何もしません）"
  exit 0
fi

DEST="$ROOT/dev/.claude"
mkdir -p "$DEST/skills" "$DEST/agents"

# プロジェクト用 CLAUDE.md
if [ ! -f "$DEST/CLAUDE.md" ]; then
  cat > "$DEST/CLAUDE.md" <<'EOF'
# プロジェクト固有 Claude 設定

このプロジェクトは個人のグローバル設定（`~/.claude/CLAUDE.md`）を **意図的に引き継いでいません**。
チーム全員が同じ前提で作業するために、必要な指示はすべてこのファイルとプロジェクト内 `.claude/` 配下に置きます。

## 必須遵守事項

- **TDD**: 先にテストを書いて赤を確認、最小実装で緑、リファクタ。E2E も同様。
- **Hono Clean Architecture**: domain → application → infrastructure / interfaces。
- **Drizzle のみ + `drizzle-kit migrate` のみ**（`push` 禁止）。
- **Nix pure**: `direnv allow` で自動。Apple toolchain（Xcode / iOS Simulator）のみ例外。
- **AI 風デザイン禁止**: Lucide Icons のみ、グラデーション・ネオン・絵文字禁止。
- **JSDoc / TSDoc 必須、関数内コメント禁止、説明はすべて日本語**。
- **Git**: rebase / reset --hard / push --force 禁止。コンフリクトはマージコミット。

## 利用可能スキル / エージェント（プロジェクトローカル）

`.claude/skills/` と `.claude/agents/` 配下にハーネス系のものをコピー済み。
チーム外からは見えないので、新メンバーもこれだけで作業可能。

詳細は `.harness/docs/` を参照。
EOF
fi

# 最小限の settings.json（global の hooks を一旦無効化したい場合の足がかり）
if [ ! -f "$DEST/settings.json" ]; then
  cat > "$DEST/settings.json" <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings",
  "_comment": "プロジェクト固有 Claude 設定。global の hooks は引き継がない方針なら hooks を空に保つこと。"
}
EOF
fi

# harness 系 skills を dev/.claude/skills/ にコピー（globals に依存しない）
copied_skill_count=0
if [ -d "$HOME/.claude/skills" ]; then
  for src_skill in "$HOME/.claude/skills"/harness-* "$HOME/.claude/skills"/my-harness-init; do
    [ -d "$src_skill" ] || continue
    skill_name=$(basename "$src_skill")
    if [ ! -d "$DEST/skills/$skill_name" ]; then
      cp -R "$src_skill" "$DEST/skills/$skill_name"
      copied_skill_count=$((copied_skill_count + 1))
    fi
  done
fi
echo "[setup-claude] skills を $copied_skill_count 個コピー"

# harness 系 agents を dev/.claude/agents/ にコピー
copied_agent_count=0
if [ -d "$HOME/.claude/agents" ]; then
  for src_agent in "$HOME/.claude/agents"/harness-*.md; do
    [ -f "$src_agent" ] || continue
    agent_name=$(basename "$src_agent")
    if [ ! -f "$DEST/agents/$agent_name" ]; then
      cp "$src_agent" "$DEST/agents/$agent_name"
      copied_agent_count=$((copied_agent_count + 1))
    fi
  done
fi
echo "[setup-claude] agents を $copied_agent_count 個コピー"

echo "[setup-claude] dev/.claude/ にプロジェクト独立設定を配置完了"
echo "[setup-claude]   個人の ~/.claude/* は依然として併用される（Claude Code のマージ仕様）"
echo "[setup-claude]   完全 isolate したい場合は dev/.claude/CLAUDE.md に追加指示を書いてください"
