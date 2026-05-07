#!/usr/bin/env bash
# Resolve conflicts using merge commits only — rebase/reset are prohibited
# Usage: bash .harness/scripts/resolve-conflict.sh <feature-worktree> [base=dev]
set -euo pipefail
WT="${1:?feature worktree required}"
BASE="${2:-dev}"

cd "$WT"
git fetch origin "$BASE"
# Incorporate changes via merge commit without any rebase or reset
git merge --no-ff "origin/$BASE" -m "merge: resolve conflicts with $BASE (no rebase/reset)"
echo "Conflict resolved via merge commit. Resolve markers, then commit + push."
