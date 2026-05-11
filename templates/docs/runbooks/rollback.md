# Rollback

**Rule:** roll back first, diagnose later. Production stability outranks
your curiosity.

## Decision tree

```
Is canary still partial (< 100 %)?
  YES → reset canary to 0 %  (90 sec, instant relief)
        ↓
  NO  → revert merge commit on main and re-deploy
        ↓
        → if fix is in flight, deploy hotfix branch (runbooks/hotfix.md)
```

## A. Roll back canary (fastest, < 2 min)

```bash
# Get the previous deployment id
nix develop --command pnpm exec wrangler deployments list --env production | head -5

# Roll back
nix develop --command pnpm exec wrangler rollback <previous-deployment-id> --env production
```

Verify:
- `wrangler tail` shows error rate dropping
- Synthetic checks recover within 5 min

## B. Revert merge commit (slower, 10-20 min)

Use only if the canary is already at 100 %.

```bash
git checkout main
git fetch origin

# Identify the merge commit
git log --merges --first-parent main -5

# Revert it
git revert -m 1 <merge-sha>
git push origin main
```

A revert PR auto-opens. Apply `approved-for-prod` (skip the 24-h soak
since this is a known-good prior state) and merge.

CI runs the canary 10 → 100 path automatically. Watch for the same checks.

## C. Database rollback

Schema changes are migrations only (`rules/drizzle.md`). To roll back:

```bash
# Inspect the failing migration
nix develop --command pnpm exec drizzle-kit migrations list

# Revert the migration manually (write a new migration that reverses it).
# DO NOT delete the failing migration file from drizzle/.
nix develop --command pnpm exec drizzle-kit generate --name revert_<original-name>
nix develop --command pnpm exec wrangler d1 migrations apply DB --env production --remote
```

## Forbidden during rollback

- `git reset --hard` — overwrites history
- `git push --force` — overwrites remote
- `drizzle-kit push` — bypasses migration history
- "Just one more fix" without rollback first

## Post-rollback

- [ ] Status page updated to "monitoring" then "resolved" after 30 min clean
- [ ] Postmortem scheduled (`runbooks/postmortem.md`)
- [ ] Original PR linked to the revert PR + the future fix PR
