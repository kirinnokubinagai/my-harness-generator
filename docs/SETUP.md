# Setup Guide (GitHub Actions Variables / Secrets)

This guide describes how to interactively register the GitHub Variables / Secrets needed to run the harness using the `gh` CLI.
**Only key names are listed in the tables below — enter values interactively as you register them.**

## Variables (public, referenced at build time)

| Name | Purpose | Example |
|------|---------|---------|
| `DEV_URL` | Base URL of the dev environment | `https://dev.example.com` |
| `STAGE_URL` | Base URL of the stage environment (OWASP ZAP target) | `https://stage.example.com` |
| `PROD_URL` | Production URL | `https://example.com` |
| `STAGE_IPA_PATH` | Path to iOS build artifact to pass to MobSF | `build/app.ipa` |
| `R2_BACKUP_BUCKET` | R2 bucket name for DB backup storage | `harness-prod-backups` |
| `AGE_RECIPIENTS` | age public keys for backup encryption (space-separated) | `age1xxx age1yyy` |

Registration commands:

```bash
gh variable set DEV_URL --repo <owner/repo>
gh variable set STAGE_URL --repo <owner/repo>
gh variable set PROD_URL --repo <owner/repo>
gh variable set STAGE_IPA_PATH --repo <owner/repo>
gh variable set R2_BACKUP_BUCKET --repo <owner/repo>
gh variable set AGE_RECIPIENTS --repo <owner/repo>
```

`gh variable set` prompts interactively for the value, making it safe to copy and paste.

## Secrets (must be encrypted, never logged)

| Name | Purpose |
|------|---------|
| `ANTHROPIC_API_KEY` | API key for Claude Code Action |
| `RESEND_API_KEY` | Email sending for password resets, etc. |
| `EMAIL_FROM_ADDRESS` | Sender address (under an authenticated domain) |
| `PROD_DATABASE_URL` | Production DB (for pg_dump) |
| `STAGE_DATABASE_URL` | Stage DB (restore target) |
| `R2_ACCESS_KEY_ID` | Cloudflare R2 access key |
| `R2_SECRET_ACCESS_KEY` | R2 secret |
| `R2_ENDPOINT_URL` | R2 endpoint URL |
| `AGE_SECRET_KEY_STAGE` | age private key for stage restore |
| `MOBSF_API_KEY` | MobSF authentication |
| `CLOUDFLARE_API_TOKEN` | For Cloudflare operations via Alchemy v2 (`bunx alchemy deploy`) |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID (read by Alchemy v2 alongside the API token) |

Registration commands:

```bash
gh secret set ANTHROPIC_API_KEY --repo <owner/repo>
gh secret set RESEND_API_KEY --repo <owner/repo>
gh secret set EMAIL_FROM_ADDRESS --repo <owner/repo>
gh secret set PROD_DATABASE_URL --repo <owner/repo>
gh secret set STAGE_DATABASE_URL --repo <owner/repo>
gh secret set R2_ACCESS_KEY_ID --repo <owner/repo>
gh secret set R2_SECRET_ACCESS_KEY --repo <owner/repo>
gh secret set R2_ENDPOINT_URL --repo <owner/repo>
gh secret set AGE_SECRET_KEY_STAGE --repo <owner/repo>
gh secret set MOBSF_API_KEY --repo <owner/repo>
gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo>
```

## Branch Protection

Run this immediately after creating the repository:

```bash
bash .harness/scripts/setup-branch-protection.sh <owner/repo>
```

This applies the following settings in bulk to main / stage / dev:
- Force-push prohibited (`allow_force_pushes=false`)
- Deletion prohibited (`allow_deletions=false`)
- Required PR reviews (main=2, stage/dev=1)
- Required status checks (quality / e2e / security / claude-review)
- Conversation resolution required (`required_conversation_resolution=true`)
- Merge commits retained (`allow_merge_commit=true`; squash/rebase prohibited)
- Automatic branch deletion after merge

## Enabling Auto-Merge

`setup-branch-protection.sh` automatically applies `allow_auto_merge=true`, so no additional action is needed.

## Resend Domain Authentication

1. Add your domain at <https://resend.com/domains>.
2. Manage the displayed DNS records (SPF / DKIM / DMARC) via Alchemy v2 by adding `Cloudflare.DnsRecords` declarations to `dev/alchemy.run.ts` (see `harness-deploy-setup`).
3. After authentication is complete, set `EMAIL_FROM_ADDRESS` to an address under that domain.

## Cloudflare R2 Backup Bucket

```bash
nix develop --command bunx alchemy deploy --stage prod
# Creates the R2Bucket("BackupBucket") declared in dev/alchemy.run.ts
```

Declaration in `dev/alchemy.run.ts` (Alchemy v2 / Effect.gen):

```typescript
const backupBucket = yield* Cloudflare.R2Bucket("BackupBucket", {
  name: "harness-prod-backups",
  location: "APAC",
});
```

Lifecycle rules (delete after 90 days) can be configured in the R2 dashboard. Alchemy v2 R2 lifecycle rule resource availability is in flux during the `2.0.0-beta.x` series — check `v2.alchemy.run` providers list before relying on it.
