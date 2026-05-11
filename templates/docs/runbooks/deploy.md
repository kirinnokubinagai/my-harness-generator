# Deploy

The harness's `/harness-deploy` automates the safe path. This runbook is the
manual fallback and the source of truth for what `/harness-deploy` is doing.

## Pre-deploy checklist

- [ ] CI on `dev` is green
- [ ] `dev/CHANGELOG.md` updated
- [ ] No open SEV1/SEV2 incidents
- [ ] Backup taken in the last 24 h (verify in R2 dashboard)
- [ ] On-call confirmed available for next 2 h

## dev → stage

```bash
git checkout stage
git fetch origin
gh pr create --base stage --head dev \
  --title "release: dev → stage $(date +%Y-%m-%d)"
```

CI runs:
1. `quality.yml` (biome + vitest + tsc)
2. `e2e.yml` (Playwright + Maestro)
3. `security.yml` (OWASP ZAP baseline + MobSF + gitleaks history)
4. `k6-smoke.yml`

When all four are green AND a human applies the `approved-for-stage` label:

```bash
gh pr review <pr> --approve
gh pr edit <pr> --add-label approved-for-stage
gh pr merge <pr> --auto --merge
```

After merge, stage auto-deploys. Verify:
- `wrangler tail --env stage` shows no error spike
- Synthetic checks green for 30 min
- p95 latency unchanged

## stage → main (after 24+ h stable on stage)

```bash
gh release create vX.Y.Z --draft --generate-notes --target stage
gh pr create --base main --head stage \
  --title "release: stage → main vX.Y.Z" \
  --body-file .github/release-pr-body.md
gh pr edit <pr> --add-label approved-for-prod
gh pr merge <pr> --auto --merge
```

CI re-runs every gate and verifies the `approved-for-prod` label.

## Canary 10 % → 100 %

```bash
nix develop --command pnpm exec wrangler deployments deploy --env production --percent 10
# 30 min observation:
nix develop --command bash .my-harness/scripts/check-canary-health.sh
# If healthy:
nix develop --command pnpm exec wrangler deployments deploy --env production --percent 100
gh release edit vX.Y.Z --draft=false
```

## Post-deploy

- [ ] Status page updated
- [ ] Sentry release tagged (release URL in PR body)
- [ ] Source maps uploaded (`pnpm dlx @sentry/wizard upload-sourcemaps`)
- [ ] SBOM attached to the GitHub Release (automatic via `sbom.yml`)
- [ ] On-call handoff doc updated in `oncall.md`

## If anything looks off

→ `runbooks/rollback.md`. Do not try to fix forward in production.
