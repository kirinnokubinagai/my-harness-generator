# Setup & Security Guide

GitHub Actions Variables / Secrets registration, branch protection, and the security policy that the harness assumes. After `/my-harness-init` (or `/my-harness-adopt`) finishes the local bootstrap, run the steps below once per repo.

## GitHub Variables (public, build-time)

| Name | Purpose | Example |
|---|---|---|
| `DEV_URL` | Base URL of the dev environment | `https://dev.example.com` |
| `STAGE_URL` | Base URL of the stage environment (OWASP ZAP target) | `https://stage.example.com` |
| `PROD_URL` | Production URL | `https://example.com` |
| `STAGE_IPA_PATH` | Path to iOS build artifact for MobSF | `build/app.ipa` |
| `R2_BACKUP_BUCKET` | R2 bucket for DB backup storage | `harness-prod-backups` |
| `AGE_RECIPIENTS` | age public keys for backup encryption (space-separated) | `age1xxx age1yyy` |

```bash
gh variable set DEV_URL --repo <owner>/<repo>
gh variable set STAGE_URL --repo <owner>/<repo>
gh variable set PROD_URL --repo <owner>/<repo>
gh variable set STAGE_IPA_PATH --repo <owner>/<repo>
gh variable set R2_BACKUP_BUCKET --repo <owner>/<repo>
gh variable set AGE_RECIPIENTS --repo <owner>/<repo>
```

`gh variable set` prompts interactively — safe to paste values.

## GitHub Secrets (encrypted, never logged)

| Name | Purpose |
|---|---|
| `ANTHROPIC_API_KEY` | Claude Code Action |
| `RESEND_API_KEY` | Email (password reset, etc.) |
| `EMAIL_FROM_ADDRESS` | Sender address (under an authenticated domain) |
| `PROD_DATABASE_URL` | Production DB (for `pg_dump`) |
| `STAGE_DATABASE_URL` | Stage DB (restore target) |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT_URL` | Cloudflare R2 |
| `AGE_SECRET_KEY_STAGE` | age private key for stage restore |
| `MOBSF_API_KEY` | MobSF authentication |
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | Alchemy v2 (`bunx alchemy deploy`) |

```bash
for s in ANTHROPIC_API_KEY RESEND_API_KEY EMAIL_FROM_ADDRESS \
         PROD_DATABASE_URL STAGE_DATABASE_URL \
         R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_ENDPOINT_URL \
         AGE_SECRET_KEY_STAGE MOBSF_API_KEY \
         CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
  gh secret set "$s" --repo <owner>/<repo>
done
```

Or use the bundled bulk helper: `bash scripts/setup-secrets.sh <owner>/<repo>`.

## Branch Protection (run once after creating the repo)

```bash
bash scripts/setup-branch-protection.sh <owner>/<repo>
```

Applies to `main` / `stage` / `dev`:
- `allow_force_pushes=false`, `allow_deletions=false`
- Required PR reviews (main=2, stage/dev=1)
- Required status checks: `quality` / `e2e` / `security` / `claude-review`
- `required_conversation_resolution=true`
- Merge commits retained (`allow_merge_commit=true`; squash & rebase off)
- `delete_branch_on_merge=true`, `allow_auto_merge=true`

Equivalent direct `gh api` invocation: `gh api repos/<o>/<r>/branches/main/protection -X PUT --input <(jq -n '...')`.

## Resend Domain Authentication

1. Add the domain at <https://resend.com/domains>.
2. Manage the displayed SPF / DKIM / DMARC records via Alchemy v2 by adding `Cloudflare.DnsRecords` to `dev/alchemy.run.ts` (see `/harness-deploy`).
3. Once authenticated, set `EMAIL_FROM_ADDRESS` to an address under that domain.

## Cloudflare R2 Backup Bucket

```bash
nix develop --command bunx alchemy deploy --stage prod
# Creates the R2Bucket("BackupBucket") declared in dev/alchemy.run.ts:
```

```typescript
const backupBucket = yield* Cloudflare.R2Bucket("BackupBucket", {
  name: "harness-prod-backups",
  location: "APAC",
});
```

Lifecycle rules (delete after N days) go in the R2 dashboard. Alchemy v2 R2 lifecycle resource availability is in flux during `2.0.0-beta.x` — check `v2.alchemy.run` provider list first.

---

# Security Policy

The harness assumes the following defense-by-layer model. Implementation lives in `rules/*.md`, the workflow templates, and pre-commit / CI hooks.

## 1. Secret Management

- Never commit plain-text `.env` (already in `.gitignore`).
- Development: local env vars via **direnv + Nix flake**.
- Sharing: only **SOPS + age**-encrypted files (`secrets/*.enc.json`) in the repo. Keys managed personally (1Password / iCloud Keychain); CI uses `AGE_SECRET_KEY_STAGE`.
- Production: **Cloudflare bindings** (Workers env), or AWS Secrets Manager / GCP Secret Manager when running off Cloudflare. Apps retrieve via IAM Role.

## 2. Authentication / Authorization

- Passwords: bcrypt cost ≥ 12.
- Sessions: HttpOnly + Secure + SameSite=Strict cookies; JWT short-lived (15 min) + refresh (7 d).
- Resource owner check mandatory; RBAC centralised in Hono middleware.

## 3. Input Validation

- All input validated with Zod (`422` on rejection; error message in `$LANG`).
- Drizzle ORM only; raw SQL must use the parameterised `sql` template.

## 4. SAST / DAST / Dependencies

| Type | Tool | When |
|---|---|---|
| SAST | Semgrep (OWASP / TypeScript ruleset) | PR → dev |
| Secrets scan | gitleaks | pre-commit + CI |
| Dependency | Trivy + Renovate | CI daily + PR |
| Container | Trivy image scan | after docker build |
| DAST | OWASP ZAP baseline + full | dev → stage merge |
| License | license-checker | before release |

## 5. Network / Infrastructure

- HTTPS enforced + HSTS preload.
- CSP starts at `default-src 'self'`; only add necessary origins.
- CORS: explicit origin list in `.env`; `*` is prohibited.
- WAF: Cloudflare WAF (OWASP Core Rule Set) or AWS WAF when off Cloudflare.
- Rate limiting: login 5 / 15 min; API overall 100 / 15 min.

## 6. Observability

- Structured logging (pino) → CloudWatch / Datadog.
- Sensitive data masked (e.g. `te***@example.com`).
- Alerts on p95 latency, error rate, auth failure count.
- Audit log (auth / permission change / data deletion) stored separately for 1 year.

## Why this configuration

- **Nix pure + SOPS**: satisfies "clean-machine" reproducibility and enables safe secret sharing through Git.
- **Semgrep + Trivy + ZAP**: OSS-only SAST / DAST / SCA coverage.
- **ZAP / E2E at stage**: side-effects surface in a production-like environment so `main` stays green.
