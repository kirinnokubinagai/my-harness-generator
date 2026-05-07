#!/usr/bin/env bash
# Summary: After new commits land on dev (e.g. after a hotfix back-merge),
#          runs `merge --no-ff origin/dev` on all feature worktrees to sync them.
#          Rebase / reset are prohibited. Conflicts must be resolved interactively by the engineer.
# Usage: bash .harness/scripts/sync-features-with-dev.sh
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
      echo "::warning:: $wt: conflict detected. Engineer must resolve via merge commit (rebase/reset prohibited)"
      EXIT_CODE=2
    fi
  ) || EXIT_CODE=$?
done

exit "$EXIT_CODE"
