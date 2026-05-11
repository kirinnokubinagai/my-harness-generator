---
name: harness-setup-secrets
description: Interactively registers GitHub Secrets / Variables. Wraps `setup-secrets.sh`. Only prompts for the secrets that are needed based on the selections in `.my-harness/.config` (USE_CODEX / USE_EMAIL / USE_DB, etc.). Fires when the user says "set up GitHub secrets", "initial setup secrets", or similar.
---

# harness-setup-secrets

Interactively registers the GitHub Secrets / Variables required for a harness-based project via the `gh` CLI. Intended to be run **once** after bootstrap is complete.

## Prerequisites

- `gh auth status` passes (logged into GitHub)
- Repository is created (`gh repo create` done)
- `<root>/.my-harness/.config` exists (bootstrap complete)

## Invocation

```bash
cd <root>
bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>
```

## Interactive prompts

Only prompts for what is needed based on `.my-harness/.config` selections:

### Common (all projects)
- `DEV_URL` / `STAGE_URL` / `PROD_URL` (vars)

### When USE_CLAUDE_ACTION=yes
- `CLAUDE_CODE_OAUTH_TOKEN` (OAuth) or `ANTHROPIC_API_KEY` (API key)

### When USE_EMAIL=yes
- `RESEND_API_KEY` / `EMAIL_FROM_ADDRESS`

### When USE_DB=yes (DB_KIND=d1)
- `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_D1_DATABASE_ID`
- `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_ENDPOINT_URL`
- `R2_BACKUP_BUCKET` (var) / `AGE_RECIPIENTS` (var)
- `AGE_SECRET_KEY_STAGE`

### When USE_IOS / USE_ANDROID=yes (mobile)
- `MOBSF_API_KEY`

### When USE_IOS=yes
- `APP_STORE_CONNECT_API_KEY_ID` / `_ISSUER_ID` / `_KEY_BASE64`
- `MATCH_PASSWORD` / `MATCH_GIT_BASIC_AUTHORIZATION`

## How it works

For each secret/var, launches `gh secret set` / `gh variable set` → enter value interactively (stdin or paste). Empty input skips that secret.

## Secret management best practices

- Enter values interactively so they are not left in terminal history
- For values that need to be shared, use **SOPS + age** encrypted files (`secrets/*.enc.json`) and decrypt in CI
- See `<root>/.my-harness/docs/SETUP.md` for details

## Related

- Branch protection: `harness-branch-protection`
- No-hardcode policy: see `rules/no-hardcoded-secrets.md`
