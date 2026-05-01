#!/usr/bin/env bash
# 概要: プラットフォームに依存しない共通ファイル（Biome / Husky / Nix / Gitleaks / GitHub テンプレ等）を dev に配布。
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"
cd "$ROOT"

# Biome
cp -n "$HARNESS_DIR/templates/biome/biome.json" dev/biome.json

# Husky
mkdir -p dev/.husky
cp -n "$HARNESS_DIR/templates/husky/pre-commit" dev/.husky/pre-commit
cp -n "$HARNESS_DIR/templates/husky/pre-push" dev/.husky/pre-push
cp -n "$HARNESS_DIR/templates/husky/commit-msg" dev/.husky/commit-msg
chmod +x dev/.husky/pre-commit dev/.husky/pre-push dev/.husky/commit-msg

# Nix + direnv
cp -n "$HARNESS_DIR/templates/nix/flake.nix" dev/flake.nix
cp -n "$HARNESS_DIR/templates/nix/.envrc" dev/.envrc

# 機密検出
cp -n "$HARNESS_DIR/templates/security/gitleaks.toml" dev/.gitleaks.toml
cp -n "$HARNESS_DIR/templates/security/sops.yaml" dev/.sops.yaml

# Commitlint
cp -n "$HARNESS_DIR/templates/commitlint.config.cjs" dev/commitlint.config.cjs

# tsconfig
cp -n "$HARNESS_DIR/templates/typescript/tsconfig.json" dev/tsconfig.json
cp -n "$HARNESS_DIR/templates/typescript/tsconfig.build.json" dev/tsconfig.build.json

# .gitignore
cp -n "$HARNESS_DIR/templates/dotgitignore" dev/.gitignore

# GitHub
mkdir -p dev/.github/workflows dev/.github/ISSUE_TEMPLATE
cp -n "$HARNESS_DIR/templates/github/pull_request_template.md" dev/.github/pull_request_template.md
cp -n "$HARNESS_DIR/templates/github/workflows/"*.yml dev/.github/workflows/
cp -n "$HARNESS_DIR/templates/issues/parent.md"  dev/.github/ISSUE_TEMPLATE/parent.md
cp -n "$HARNESS_DIR/templates/issues/child.md"   dev/.github/ISSUE_TEMPLATE/child.md
cp -n "$HARNESS_DIR/templates/issues/hotfix.md"  dev/.github/ISSUE_TEMPLATE/hotfix.md

echo "[setup-common] 完了"
