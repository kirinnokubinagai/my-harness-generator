#!/usr/bin/env bash
# 概要: dev に新しいコミットが入った（特に hotfix back-merge 後）あと、
#       全 feature worktree に対して `merge --no-ff origin/dev` を流して同期する。
#       rebase / reset は禁止。衝突は engineer に対話的に解消させる。
# 使い方: bash .harness/scripts/sync-features-with-dev.sh
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel | sed 's,/dev$,,')
cd "$ROOT"

git fetch origin dev

EXIT_CODE=0
for wt in lanes/feat-*; do
  [ -d "$wt" ] || continue
  echo "[sync] $wt"
  (
    cd "$wt"
    if ! git merge --no-ff origin/dev -m "merge: sync with origin/dev (no rebase)"; then
      echo "::warning:: $wt: 衝突発生。engineer がマージコミットで解消してください（rebase/reset 禁止）"
      EXIT_CODE=2
    fi
  ) || EXIT_CODE=$?
done

exit "$EXIT_CODE"
