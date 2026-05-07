---
name: harness-sync-features
description: Pulls the latest dev commits into all feature worktrees (post-hotfix back-merge sync, periodic sync). Wraps `sync-features-with-dev.sh`. Fires when the user says "pull in dev", "sync", "back-merge", or similar.
---

# harness-sync-features

Merges `origin/dev` into **all feature worktrees** under `<root>/lanes/feat-*` using `git merge --no-ff`. Run after hotfix back-merges or during periodic maintenance.

## Invocation

```bash
cd <root>
bash .my-harness/scripts/sync-features-with-dev.sh
```

## What it does

1. `git fetch origin dev`
2. Iterates through each `lanes/feat-*` directory
3. Runs `git merge --no-ff origin/dev -m "merge: sync with origin/dev (no rebase)"` in each worktree
4. Reports conflicts as warnings (does not auto-resolve — engineers handle conflicts with `harness-resolve-conflict`)

## When to run

- Immediately **after** a hotfix has merged to main and been back-merged through main → stage → dev (dev now has new commits)
- When a long-running feature branch has drifted far from dev (roughly weekly)
- Before a release (dev → stage)

## Steps when a conflict occurs

The script returns exit code 2 on conflict:
```bash
bash .my-harness/scripts/sync-features-with-dev.sh
if [ $? -eq 2 ]; then
  echo "One or more lanes have conflicts. Use harness-resolve-conflict in each affected lane."
fi
```

Move into the conflicting lane → use the `harness-resolve-conflict` skill.

## Related

- Conflict resolution: `harness-resolve-conflict`
- Hotfix back-merge: `harness-new-hotfix`
- Git discipline: `harness-git-discipline`
