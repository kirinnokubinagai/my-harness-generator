---
name: harness-no-hardcoded-secrets
description: Absolutely prohibits hardcoding secret values, API keys, and connection strings. Only environment variables, SOPS encryption, and Secrets Manager are allowed. Pre-commit mechanically blocks violations. Fires when the user mentions "environment variable", "API key", "DATABASE_URL", "secret key", ".env", or similar.
---

# harness-no-hardcoded-secrets

**No hardcoded secrets** in any code, config, or commit under the harness.

## Non-negotiable rules

| Type | Hardcoding |
|------|-----------|
| API keys (`sk-...`, `ghp_...`, `xoxb-...`, etc.) | **Prohibited** |
| Values that should be env vars (`JWT_SECRET`, `DATABASE_URL`, etc.) | **Prohibited** |
| Credentials embedded in URLs (`https://user:pass@host`) | **Prohibited** |
| Production DSNs (`postgres://prod...`) | **Prohibited** |
| Committing a plaintext `.env` file | **Prohibited** (`.env.example` only) |
| PEM private keys | **Prohibited** |

Pre-commit mechanically blocks these (any slip-through is a bug):
- `.gitleaks.toml` + `gitleaks protect`
- `check-forbidden-patterns.sh` (custom patterns)

## Allowed patterns

```ts
// ✅ Via environment variable
const jwtSecret = process.env.JWT_SECRET ?? (() => {
  throw new Error('JWT_SECRET is not set');
})();

// ✅ Cloudflare Workers binding
export default {
  async fetch(request, env) {
    const apiKey = env.RESEND_API_KEY;  // bound in wrangler.toml
  }
};

// ✅ SOPS decryption
const { OPENAI_API_KEY } = JSON.parse(
  await sopsDecrypt('secrets/openai.enc.json')
);
```

## Prohibited patterns

```ts
// ❌ Hardcoded value
const JWT_SECRET = "abc12345abcdefghijk";

// ❌ Hardcoded DSN
const DATABASE_URL = "postgres://user:pass@prod.db.example.com/app";

// ❌ URL credentials
fetch("https://admin:s3cret@api.example.com/x");

// ❌ Committing a plaintext .env
// Adding .env to tracked files → rejected by pre-commit
```

## Handling secrets that need to be shared

### SOPS + age (recommended)
- Commit the encrypted file `secrets/cloudflare.enc.json` to git
- Each team member manages their own decryption key (1Password / iCloud Keychain)
- CI holds `AGE_SECRET_KEY` in GitHub Secrets

### GitHub Secrets / Variables
- API keys used only at runtime → Secrets
- Non-sensitive config values (URLs, etc.) → Variables
- Details in `docs/SETUP.md`

## Required env var check at startup

```ts
const requiredEnvVars = [
  'JWT_SECRET',
  'RESEND_API_KEY',
  'CLOUDFLARE_API_TOKEN',
];
for (const name of requiredEnvVars) {
  if (!process.env[name]) {
    throw new Error(`Environment variable ${name} is not set`);
  }
}
```

## Masking (see `harness-mask` skill)

When conversations or logs might contain secret values, pipe through `mask-secrets.sh`:
```bash
echo "$content" | bash ${CLAUDE_PLUGIN_ROOT:-/my-harness-generator}/scripts/mask-secrets.sh > docs/talk/01.md
```

## Checklist

- [ ] grep for `JWT_SECRET\s*=\s*["']` across all source finds no matches
- [ ] `.env` is in `.gitignore`; only `.env.example` is committed
- [ ] Pre-commit passed with gitleaks + forbidden-patterns
- [ ] `nix develop --command bash .my-harness/scripts/check-forbidden-patterns.sh <files>` also runs in CI
