#!/usr/bin/env bash
# 子 issue 番号から feature worktree を dev 起点で作成
# 使い方: bash .harness/scripts/new-feature.sh <issue-number> <slug>
set -euo pipefail

ISSUE="${1:?issue number required}"
SLUG="${2:?slug required}"
BRANCH="feat/${ISSUE}-${SLUG}"
DIR="lanes/feat-${ISSUE}-${SLUG}"

git fetch --all --prune
git worktree add "$DIR" -b "$BRANCH" dev
echo "worktree at $DIR (branch=$BRANCH from dev)"
