---
name: harness-check-secrets
description: Scans files for hardcoded env var values, API keys, production DSNs, and plaintext .env files. Wraps `check-forbidden-patterns.sh`. Fires when the user mentions "secrets check", "scan for secrets", "detect hardcoded values", or similar.
---

# harness-check-secrets

Detects hardcoded secret patterns that `gitleaks` may miss. Runs automatically as a pre-commit hook, but can also be called manually by Claude before committing.

## Invocation

```bash
bash <root>/.my-harness/scripts/check-forbidden-patterns.sh <files...>
```

Examples:
```bash
bash .my-harness/scripts/check-forbidden-patterns.sh src/auth.ts src/db/client.ts
# Target all changed files
bash .my-harness/scripts/check-forbidden-patterns.sh $(git diff --name-only)
```

## What it detects

- Hardcoded env var values (e.g. `JWT_SECRET = "abc..."`)
- Credentials embedded in URLs (`https://user:pass@host`)
- Production DSNs (`postgres://user:pass@prod...`)
- Committed plaintext `.env` / `.env.local` files (`.env.example` is allowed)

## Exit codes

- exit 0: OK — no secrets found
- exit 1: Violation detected — prints the offending location and remediation steps to stderr

## Defense layers

| Mechanism | What it prevents | When |
|-----------|-----------------|------|
| `scripts/mask-secrets.sh` (used by the conversation logging hook) | Secrets leaking into conversations / docs/talk | Before writing |
| This skill | Secrets hardcoded in source files | Before commit |
| `gitleaks` (pre-commit) | Known patterns (API key strings) | At commit time |
| Pre-push history scan | Already-committed leaks | At push time |
| `scheduled-secrets-scan.yml` | Final scan of entire history | Daily |

## Remediation steps when a violation is found

1. Move the hardcoded value to an environment variable
2. Move it to a SOPS-encrypted file (`*.enc.json`)
3. See `harness-no-hardcoded-secrets` skill for details

## Related

- Masking: `scripts/mask-secrets.sh` (invoked by the conversation logging hook)
- No-hardcode policy: `harness-no-hardcoded-secrets`
