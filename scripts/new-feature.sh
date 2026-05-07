#!/usr/bin/env bash
# Creates a feature worktree from dev based on a child issue number
# Usage: bash .harness/scripts/new-feature.sh <issue-number> <slug>
set -euo pipefail

ISSUE="${1:?issue number required}"
SLUG="${2:?slug required}"
BRANCH="feat/${ISSUE}-${SLUG}"
DIR="lanes/feat-${ISSUE}-${SLUG}"

git fetch --all --prune
git worktree add "$DIR" -b "$BRANCH" dev
echo "worktree at $DIR (branch=$BRANCH from dev)"
