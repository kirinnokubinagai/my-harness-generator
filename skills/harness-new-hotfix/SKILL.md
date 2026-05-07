---
name: harness-new-hotfix
description: Creates a main-based worktree for emergency production fixes. Wraps `new-hotfix.sh`. Fires when the user says "hotfix", "production incident", "emergency fix", "fix from main", or similar.
---

# harness-new-hotfix

Stands up a `hotfix/<issue>-<slug>` worktree branched from main for high-urgency production incident fixes.

## Differences from a normal feature

| Item | Normal feature | Hotfix |
|------|---------------|--------|
| Base branch | dev | **main** |
| PR target | dev | **main** |
| Stage gate | Required | Can be skipped |
| OWASP ZAP / E2E | Pre-merge | Post-merge immediately |
| SLA | Normal | **Within 24 hours** |
| Parent issue | Required upfront | Created after as post-mortem |

## Invocation

```bash
cd <root>
bash .my-harness/scripts/new-hotfix.sh <issue-number> <slug>
# → Creates worktree at lanes/hotfix-<issue>-<slug>/ from main
```

## Post-completion flow (must follow exactly)

1. Fix + minimal tests (regression test required)
2. `git push` → `gh pr create --base main`
3. **Emergency approval** + minimal gate CI (biome / vitest / tsc / trivy) passes → merge
4. **Run OWASP ZAP / E2E immediately post-merge** (rollback immediately if failing)
5. **Back-merge (always `git merge --no-ff`, rebase / reset prohibited)**:
   ```bash
   git checkout stage && git fetch origin
   git merge --no-ff origin/main -m "merge: hotfix back-merge main → stage"
   git push origin stage
   git checkout dev
   git merge --no-ff origin/stage -m "merge: hotfix back-merge stage → dev"
   git push origin dev
   ```
6. **File a post-mortem parent issue within 24 hours** and expand into prevention child issues

## Prohibited

- Direct push to main
- `git rebase` / `git reset --hard` / `git push --force`
- Skipping the back-merge (causes conflicts on the next release)

## Related

- Normal development: `harness-new-feature`
- Resolving conflicts: `harness-resolve-conflict`
- Git discipline: `harness-git-discipline`
