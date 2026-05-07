# Hotfix Workflow

## Guiding Principle

The normal flow is feat → dev → stage → main. However, for emergency fixes in production, time constraints make following this order impractical.
The following **limited exception flow** is used.

## Flow

1. **Create issue**: Add the `hotfix/` label and create as a standalone issue without a parent. SLA is 24 hours.
2. **Create worktree**: Branch from `main`.
   ```bash
   git worktree add lanes/hotfix-<issue> -b hotfix/<issue> main
   ```
3. **Fix + minimal tests**: Minimize the scope of impact; adding new features is strictly prohibited. husky pre-commit / pre-push hooks are required.
4. **PR 1: hotfix/<issue> → main**
   - Human (you) emergency approval is required
   - Gates: format / lint / unit test / typecheck / Trivy
   - OWASP ZAP / E2E **run immediately post-merge** (non-blocking, but a failure triggers an immediate rollback)
5. **Back-merge (rebase prohibited; merge commits only)**:
   ```bash
   # main → stage
   git checkout stage && git merge --no-ff main
   # stage → dev
   git checkout dev && git merge --no-ff stage
   ```
6. **Post-mortem**: Create a parent issue within 24 hours and develop preventive measures as child issues.

## Differences from Normal Flow

| Item | Normal | Hotfix |
|------|--------|--------|
| Base branch | dev | main |
| PR target | dev | main |
| Stage gate | Required | Skippable (emergency only) |
| ZAP/E2E | pre-merge | post-merge immediately |
| Parent/child issue | Required | Created post-mortem |

## Prohibited

- `git reset --hard`, `git rebase`, `git push --force`, and `--force-with-lease` are also prohibited in principle.
- Never edit main directly (always cut a hotfix branch).
- Never skip the back-merge (without it, the fix won't reach dev/stage and the bug will recur).
