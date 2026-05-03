#!/usr/bin/env bash
# 概要: プラットフォームに依存しない共通ファイル（Biome / Husky / Nix / Gitleaks / GitHub テンプレ等）を dev に配布。
#       既に存在するファイルは上書きしない（ユーザー編集を保護）ため、cp_if_missing で安全にコピーする。
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"
cd "$ROOT"

# 概要: 宛先が既に存在しない場合のみコピーする（macOS / Linux 両対応、set -e 安全）。
#       cp -n は macOS で「既存時 exit 1」を返すため使えない。
cp_if_missing() {
  local src="$1"; local dst="$2"
  if [ ! -e "$dst" ]; then
    cp "$src" "$dst"
  fi
}

# 概要: glob 展開でディレクトリ全体を「無ければコピー」する。
cp_glob_if_missing() {
  local src_glob="$1"; local dst_dir="$2"
  mkdir -p "$dst_dir"
  for src in $src_glob; do
    [ -e "$src" ] || continue
    cp_if_missing "$src" "$dst_dir/$(basename "$src")"
  done
}

# Biome
cp_if_missing "$HARNESS_DIR/templates/biome/biome.json" dev/biome.json

# Husky
mkdir -p dev/.husky
cp_if_missing "$HARNESS_DIR/templates/husky/pre-commit" dev/.husky/pre-commit
cp_if_missing "$HARNESS_DIR/templates/husky/pre-push"   dev/.husky/pre-push
cp_if_missing "$HARNESS_DIR/templates/husky/commit-msg" dev/.husky/commit-msg
chmod +x dev/.husky/pre-commit dev/.husky/pre-push dev/.husky/commit-msg 2>/dev/null || true

# Nix + direnv
cp_if_missing "$HARNESS_DIR/templates/nix/flake.nix" dev/flake.nix
cp_if_missing "$HARNESS_DIR/templates/nix/.envrc"    dev/.envrc

# 機密検出
cp_if_missing "$HARNESS_DIR/templates/security/gitleaks.toml" dev/.gitleaks.toml
cp_if_missing "$HARNESS_DIR/templates/security/sops.yaml"     dev/.sops.yaml

# Commitlint
cp_if_missing "$HARNESS_DIR/templates/commitlint.config.cjs" dev/commitlint.config.cjs

# tsconfig
cp_if_missing "$HARNESS_DIR/templates/typescript/tsconfig.json"       dev/tsconfig.json
cp_if_missing "$HARNESS_DIR/templates/typescript/tsconfig.build.json" dev/tsconfig.build.json

# .gitignore
cp_if_missing "$HARNESS_DIR/templates/dotgitignore" dev/.gitignore

# GitHub
mkdir -p dev/.github/workflows dev/.github/ISSUE_TEMPLATE
cp_if_missing      "$HARNESS_DIR/templates/github/pull_request_template.md"     dev/.github/pull_request_template.md
cp_glob_if_missing "$HARNESS_DIR/templates/github/workflows/*.yml"              dev/.github/workflows

# GitHub Actions ヘルパー（USE_GITHUB_ISSUES 分岐用）
mkdir -p dev/.github/scripts
cp_if_missing "$HARNESS_DIR/templates/github/scripts/maybe-create-issue.js" dev/.github/scripts/maybe-create-issue.js
cp_if_missing      "$HARNESS_DIR/templates/issues/parent.md"                    dev/.github/ISSUE_TEMPLATE/parent.md
cp_if_missing      "$HARNESS_DIR/templates/issues/child.md"                     dev/.github/ISSUE_TEMPLATE/child.md
cp_if_missing      "$HARNESS_DIR/templates/issues/hotfix.md"                    dev/.github/ISSUE_TEMPLATE/hotfix.md

echo "[setup-common] 完了"
