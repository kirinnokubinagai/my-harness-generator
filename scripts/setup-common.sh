#!/usr/bin/env bash
# Summary: Distributes platform-independent common files (Biome / Husky / Nix / Gitleaks / GitHub templates, etc.) to dev.
#          Uses cp_if_missing to safely copy only when the destination does not exist,
#          so that user edits are preserved (existing files are never overwritten).
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"
cd "$ROOT"

# Summary: Copy only if the destination does not already exist (works on both macOS and Linux, safe with set -e).
#          cp -n on macOS returns exit 1 when the destination exists, so it cannot be used.
cp_if_missing() {
  local src="$1"; local dst="$2"
  if [ ! -e "$dst" ]; then
    cp "$src" "$dst"
  fi
}

# Summary: Copy an entire directory via glob expansion, only for files that do not already exist.
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

# Secret detection
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

# GitHub Actions helper (for USE_GITHUB_ISSUES branching)
mkdir -p dev/.github/scripts
cp_if_missing "$HARNESS_DIR/templates/github/scripts/maybe-create-issue.js" dev/.github/scripts/maybe-create-issue.js
cp_if_missing      "$HARNESS_DIR/templates/issues/parent.md"                    dev/.github/ISSUE_TEMPLATE/parent.md
cp_if_missing      "$HARNESS_DIR/templates/issues/child.md"                     dev/.github/ISSUE_TEMPLATE/child.md
cp_if_missing      "$HARNESS_DIR/templates/issues/hotfix.md"                    dev/.github/ISSUE_TEMPLATE/hotfix.md

echo "[setup-common] Done"
