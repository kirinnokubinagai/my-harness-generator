---
name: harness-deploy-execute
description: Executes the staged deployment pipeline: dev → stage → main. Stage requires OWASP ZAP / Playwright / Maestro; main requires human approval + canary 10% → 100%. Fires when the user says "deploy", "release", "promote to stage", "push to production", or similar.
---

# harness-deploy-execute

Stages releases dev → stage → main, after implementation and `harness-deploy-setup` are done.

## Prerequisites

- `harness-deploy-setup` complete (`bunx alchemy deploy --stage prod` ran, `DEPLOY_READY=yes` in `.my-harness/.config`).
- All features merged to `dev`; CI green.

## A. dev → stage (automated, human-approved)

```bash
git checkout stage
git fetch origin
gh pr create --base stage --head dev --title "release: dev → stage <date>"
```

`pr-to-stage.yml` runs quality (biome / vitest / tsc), e2e (Playwright + Maestro), security (OWASP ZAP + MobSF + history gitleaks). Green CI alone is **not** enough — the `approved-for-stage` label is required (human gate). CI failures auto-file an issue via `maybe-create-issue.js`.

```bash
gh pr review <pr-number> --approve
gh pr edit <pr-number> --add-label approved-for-stage
gh pr merge <pr-number> --auto --merge
```

After the merge, stage deploys automatically:
- Cloudflare Pages picks up the stage branch
- `wrangler d1 migrations apply DB --env staging --remote`
- Restore production backup from R2 (manual `wrangler r2 object get` + `wrangler d1 execute`; the plugin no longer ships a scheduled backup workflow)
- TestFlight build upload (when `USE_IOS=yes`)

## B. stage → main (after 24h+ stable on stage)

Verify the latest stage commit ran stably on staging for at least 24 hours: metrics (p95 / error rate / auth failures) show no anomalies; ZAP / E2E remain green.

```bash
gh release create vX.Y.Z --draft --generate-notes --target stage
gh pr create --base main --head stage \
  --title "release: stage → main vX.Y.Z" \
  --body-file .github/release-pr-body.md
gh pr edit <pr-number> --add-label approved-for-prod
gh pr merge <pr-number> --auto --merge
```

`pr-to-main.yml` re-runs all gates (reusing `pr-to-stage`) and verifies the `approved-for-prod` label.

## C. Canary 10% → 100%

```bash
# 10% first
nix develop --command pnpm exec wrangler deployments deploy --env production --percent 10
# 30 min at 10% → check metrics
nix develop --command bash .my-harness/scripts/check-canary-health.sh
# 100% if healthy
nix develop --command pnpm exec wrangler deployments deploy --env production --percent 100
# Publish the GitHub Release
gh release edit vX.Y.Z --draft=false
```

## Rollback

Use `git revert` only (rebase / reset prohibited per `rules/nix-pure.md` + `docs/HOTFIX.md`):

```bash
git checkout main
git revert -m 1 <merge-sha>
git push origin main
```

Or roll the canary back to the previous deployment:

```bash
nix develop --command pnpm exec wrangler rollback <previous-deployment-id>
```

## Emergency fixes

Follow `docs/HOTFIX.md`: branch `hotfix/<short>` from `main`, PR target `main`, then merge-commit back to `stage` and `dev`.

## Checklist

**dev → stage**
- [ ] All CI on dev green
- [ ] PR `--base stage --head dev`
- [ ] OWASP ZAP / Playwright / Maestro green
- [ ] `approved-for-stage` applied (human)
- [ ] Stage updated via auto-merge

**stage → main**
- [ ] 24+ h stable on stage, metrics clean
- [ ] `gh release create --draft` done
- [ ] `approved-for-prod` applied
- [ ] Main updated via auto-merge

**Canary**
- [ ] 10% for 30 min, metrics clean
- [ ] Promoted to 100%
- [ ] `gh release edit --draft=false` done

## Related

- Setup: `harness-deploy-setup`
- Hotfix: `docs/HOTFIX.md`
- Git discipline: `rules/nix-pure.md` + `docs/HOTFIX.md`
- Secrets: `scripts/setup-secrets.sh` + `docs/SETUP.md`
- Infrastructure details: `docs/INFRA.md`
