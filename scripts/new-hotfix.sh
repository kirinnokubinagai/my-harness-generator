#!/usr/bin/env bash
# Creates a hotfix worktree from main
set -euo pipefail
ISSUE="${1:?issue number required}"
SLUG="${2:?slug required}"
BRANCH="hotfix/${ISSUE}-${SLUG}"
DIR="lanes/hotfix-${ISSUE}-${SLUG}"

git fetch --all --prune
git worktree add "$DIR" -b "$BRANCH" main
echo "hotfix worktree at $DIR (branch=$BRANCH from main)"
