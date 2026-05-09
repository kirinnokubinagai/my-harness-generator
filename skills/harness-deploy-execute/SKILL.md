---
name: harness-deploy-execute
description: Executes the staged deployment pipeline: dev → stage → main. Stage requires OWASP ZAP / Playwright / Maestro; main requires human approval + canary 10% → 100%. Fires when the user says "deploy", "release", "promote to stage", "push to production", or similar.
---

# harness-deploy-execute

The skill for carrying out staged releases to each environment after implementation and `harness-deploy-setup` are complete.

## Prerequisites

- `harness-deploy-setup` is done (`bunx alchemy deploy --stage prod` for the initial infra bootstrap, `DEPLOY_READY=yes` in `.my-harness/.config`)
- All features are merged to dev / all CI is green

## The 3 deployment stages

### A. dev → stage (automated but requires human approval)

```bash
git checkout stage
git fetch origin
gh pr create --base stage --head dev --title "release: dev → stage <date>"
```

`pr-to-stage.yml` runs:
- quality (biome / vitest / tsc)
- e2e (Playwright + Maestro)
- security (OWASP ZAP + MobSF + history gitleaks)
- Even if all green, **`approved-for-stage` label is required** (human approval)

On CI failure, `maybe-create-issue.js` automatically creates an issue (or a file in `docs/task/auto/`).

Human approval:
```bash
gh pr review <pr-number> --approve
gh pr edit <pr-number> --add-label approved-for-stage
gh pr merge <pr-number> --auto --merge
```

After the stage merge, the stage environment deploys automatically:
- Cloudflare Pages picks up the stage branch
- D1 stage migration (`wrangler d1 migrations apply DB --env staging --remote`)
- Restore production backup from R2 (`restore-to-stage` job in `scheduled-db-backup.yml`)
- TestFlight build upload (when USE_IOS=yes)

### B. stage → main (after 24+ hours of stable operation on stage)

Verify that the latest stage commit has been running stably in the staging environment for **at least 24 hours**:
- Metrics (p95 / error rate / auth failures) show no anomalies
- ZAP / E2E remain green (re-run is fine)

```bash
gh release create vX.Y.Z --draft --generate-notes --target stage
gh pr create --base main --head stage \
  --title "release: stage → main vX.Y.Z" \
  --body-file .github/release-pr-body.md
gh pr edit <pr-number> --add-label approved-for-prod
gh pr merge <pr-number> --auto --merge
```

`pr-to-main.yml` re-runs all gates (reusing pr-to-stage) and verifies the `approved-for-prod` label.

### C. Canary 10% → 100%

Production deployment after the main merge is gradual:

```bash
# Cloudflare Pages traffic splitting (or Workers versioned deployment)
nix develop --command pnpm exec wrangler deployments deploy --env production --percent 10
```

30 minutes at 10% → check metrics:
```bash
nix develop --command bash .my-harness/scripts/check-canary-health.sh
```

If healthy:
```bash
nix develop --command pnpm exec wrangler deployments deploy --env production --percent 100
```

Publish the GitHub Release:
```bash
gh release edit vX.Y.Z --draft=false
```

## Rollback

On problems, use `git revert` (rebase / reset prohibited per `harness-git-discipline`):

```bash
git checkout main
git revert -m 1 <merge-sha>     # Revert the merge commit
git push origin main
```

Or roll the canary back from 100% to the previous deployment:
```bash
nix develop --command pnpm exec wrangler rollback <previous-deployment-id>
```

## Emergency fixes use `harness-new-hotfix`

For urgent fixes that bypass the normal deploy flow, use `harness-new-hotfix` (not this skill). See `docs/HOTFIX.md`.

## Checklist

### dev → stage
- [ ] All CI on dev is green
- [ ] PR created with `--base stage --head dev`
- [ ] OWASP ZAP / Playwright / Maestro green
- [ ] `approved-for-stage` label applied (human approval)
- [ ] Stage updated via auto-merge

### stage → main
- [ ] Stage environment running for 24+ hours
- [ ] Metrics show no anomalies
- [ ] `gh release create --draft` done
- [ ] `approved-for-prod` label applied
- [ ] Main updated via auto-merge

### Canary
- [ ] Monitored at 10% for 30 minutes
- [ ] Error rate / latency show no anomalies
- [ ] Promoted to 100%
- [ ] `gh release edit --draft=false` done

## Related skills

- Setup: `harness-deploy-setup`
- Hotfix: `harness-new-hotfix`
- Git discipline: `harness-git-discipline`
- Secrets: `harness-setup-secrets`
- Infrastructure details: `docs/INFRA.md`
