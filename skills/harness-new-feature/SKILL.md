---
name: harness-new-feature
description: Creates a dev-based feature worktree and stands up one parallel development lane. Wraps `new-feature.sh`. Fires when the user says "start a new feature", "pick up an issue", "create a feature branch", "enter a parallel lane", or similar.
---

# harness-new-feature

Takes a child issue number and slug, and creates a worktree at `<root>/lanes/feat-<issue>-<slug>/` branched from dev.

## Prerequisites

- `<root>/.my-harness/scripts/new-feature.sh` is executable (distributed by bootstrap)
- Current working directory is the project root (where `.my-harness/.config` lives)

## Invocation

```bash
cd <root>
bash .my-harness/scripts/new-feature.sh <issue-number> <slug>
```

Example:
```bash
bash .my-harness/scripts/new-feature.sh 42 user-login
# → Creates worktree at lanes/feat-42-user-login/, branch feat/42-user-login (from dev)
```

## Post-creation workflow

1. `cd lanes/feat-<issue>-<slug>` to enter the worktree
2. `direnv allow` (first time only)
3. **Implement with TDD** (see `harness-tdd` skill)
4. **Follow all conventions** (`harness-jsdoc` / `harness-hono-clean-arch` / `harness-drizzle-rules`, etc.)
5. `git add` / `git commit` (husky pre-commit enforces format/lint/test/secrets)
6. `git push` to push the feat branch
7. `gh pr create --base dev` to open a PR (**PR target must always be dev**)

## When running 4 parallel lanes

The `harness-team-lead` agent distributes 4 child issues across 4 lanes. Each lane's engineer uses this skill to set up their worktree.

## Conventions

- Base branch must **always be dev** (branching from main / stage is prohibited except for hotfixes)
- Branch naming follows the unified pattern `feat/<issue>-<slug>`
- After merge, clean up with `git worktree remove lanes/feat-<issue>-<slug>`

## Related

- Starting a hotfix: `harness-new-hotfix`
- Resolving conflicts: `harness-resolve-conflict`
- Pulling in dev updates: `harness-sync-features`
