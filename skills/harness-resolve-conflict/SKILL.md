---
name: harness-resolve-conflict
description: Resolves conflicts using merge commits only. Wraps `resolve-conflict.sh`. Absolutely prohibits `git rebase` / `git reset` / `git push --force`. Fires when the user mentions "conflict", "merge conflict", "rebase alternative", or similar.
---

# harness-resolve-conflict

All conflict resolution under the harness uses **merge commits only**. `git rebase` / `git reset` / `git push --force` are all prohibited (following `harness-git-discipline`).

## Invocation

```bash
bash <root>/.my-harness/scripts/resolve-conflict.sh <feature-worktree> [base=dev]
```

Example:
```bash
bash <root>/.my-harness/scripts/resolve-conflict.sh lanes/feat-42-user-login dev
```

The script:
1. Fetches the latest with `git fetch origin <base>`
2. Integrates with `git merge --no-ff origin/<base>` (not rebase)
3. If conflict markers remain, **the engineer manually resolves them, preserving the intent of both sides**
4. After resolution: `git add -A && git commit`
5. `git push origin <branch>` (no `--force` variants ever)

## Why rebase is prohibited

- History rewriting destroys other contributors' work
- Merge commits are an audit trail — "who merged what and when"
- Guarantees history integrity with 4 parallel development lanes

## Post-resolution verification

```bash
nix develop --command pnpm exec biome check .
nix develop --command pnpm exec tsc --noEmit
nix develop --command pnpm exec vitest run
```

Push only after all checks pass green.

## Same rules apply for back-merges after a hotfix

Back-merges from main → stage → dev also use `git merge --no-ff` only. See `harness-new-hotfix`.

## Related

- Git discipline: `harness-git-discipline`
- Pulling in dev with no conflicts: `harness-sync-features`
