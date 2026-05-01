#!/usr/bin/env bash
# コンフリクト解消（マージコミットのみ、rebase/reset 禁止）
# 使い方: bash .harness/scripts/resolve-conflict.sh <feature-worktree> [base=dev]
set -euo pipefail
WT="${1:?feature worktree required}"
BASE="${2:-dev}"

cd "$WT"
git fetch origin "$BASE"
# rebase / reset を一切使わずマージコミットで取り込む
git merge --no-ff "origin/$BASE" -m "merge: resolve conflicts with $BASE (no rebase/reset)"
echo "competition resolved via merge commit. Resolve markers, then commit + push."
