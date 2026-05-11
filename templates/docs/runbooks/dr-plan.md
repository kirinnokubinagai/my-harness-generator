# Disaster Recovery Plan

## Targets

| Service | RTO | RPO |
|---|---|---|
| API | 1 h | 15 min |
| DB | 4 h | 1 h |
| Object storage (R2) | 8 h | 24 h |

(RTO = max time to restore service; RPO = max acceptable data loss.)

## Risk inventory

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cloudflare region failure | Low | Total outage | Multi-region Workers (default) |
| D1 corruption | Low | Total data loss | Hourly backup → R2, age-encrypted |
| R2 bucket deletion | Very low | Total backup loss | Cross-account R2 mirror weekly |
| API token leak | Medium | Full takeover | gitleaks pre-commit + Renovate scoped tokens |
| Dependency takeover | Medium | RCE | Renovate + Trivy + license check |
| DDoS | Medium | Partial outage | Cloudflare WAF + rate limiting |

## Backup schedule

- DB: hourly `wrangler d1 export` + age-encrypted upload to R2
- R2: weekly cross-account mirror
- Configuration (Cloudflare bindings, secrets): manually exported to SOPS-encrypted file in repo

## Backup verification (quarterly drill)

A backup that has never been restored is not a backup.

```bash
# Pick last week's backup
LATEST=$(nix develop --command bash .my-harness/scripts/r2-list-latest.sh harness-prod-backups)

# Decrypt to a scratch DB
nix develop --command age -d -i ~/.age/key.txt < "$LATEST" > /tmp/restore.sql

# Apply to a throwaway D1
nix develop --command pnpm exec wrangler d1 execute Restore --file=/tmp/restore.sql --remote

# Smoke check: row counts match expected
nix develop --command pnpm exec wrangler d1 execute Restore \
  --command "SELECT COUNT(*) FROM users; SELECT COUNT(*) FROM posts;" --remote
```

Document the run in `dev/docs/runbooks/dr-drills/<date>.md`.

## Disaster scenarios

### Scenario 1: D1 corruption / accidental drop

1. Page on-call SEV1.
2. Stop writes (set Worker to maintenance mode via env var).
3. Restore latest backup to a fresh D1 (above procedure).
4. Swap binding via `wrangler.jsonc` + redeploy.
5. Replay any writes lost in the RPO window from app logs (best-effort).

### Scenario 2: Cloudflare account compromise

1. Rotate all Cloudflare API tokens immediately.
2. Audit recent Workers deployments for unauthorized changes (`wrangler deployments list`).
3. Force re-auth on every developer machine (`wrangler logout`).
4. Rotate `CLOUDFLARE_API_TOKEN` in GitHub Secrets.
5. File a security incident postmortem.

### Scenario 3: Region outage (Cloudflare reports)

1. No action required (Workers are multi-region by default).
2. Monitor status.cloudflare.com.
3. If R2 reads fail in one region, customers see degraded uploads only.

## Annual review

This plan is reviewed every 12 months. Last reviewed: `<date>`.
