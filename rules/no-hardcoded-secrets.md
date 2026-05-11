# No hardcoded secrets

No hardcoded secrets in any code, config, or commit.

## Rules

| Type | Hardcoding |
|---|---|
| API keys (`sk-...`, `ghp_...`, `xoxb-...`) | **Prohibited** |
| Values that should be env vars (`JWT_SECRET`, `DATABASE_URL`, etc.) | **Prohibited** |
| Credentials in URLs (`https://user:pass@host`) | **Prohibited** |
| Production DSNs (`postgres://prod...`) | **Prohibited** |
| Plaintext `.env` committed | **Prohibited** (`.env.example` only) |
| PEM private keys | **Prohibited** |

Pre-commit blocks slip-throughs: `.gitleaks.toml` + `gitleaks protect`, and `scripts/check-forbidden-patterns.sh`.

## Allowed

```ts
// Env var
const jwtSecret = process.env.JWT_SECRET ?? (() => { throw new Error('JWT_SECRET is not set'); })();

// Cloudflare Workers binding (bound in wrangler.toml)
export default { async fetch(req, env) { const k = env.RESEND_API_KEY; } };

// SOPS decryption
const { OPENAI_API_KEY } = JSON.parse(await sopsDecrypt('secrets/openai.enc.json'));
```

## Prohibited

```ts
const JWT_SECRET = "abc12345abcdefghijk";                              // ❌
const DATABASE_URL = "postgres://user:pass@prod.db.example.com/app";   // ❌
fetch("https://admin:s3cret@api.example.com/x");                       // ❌
// committing plaintext .env                                            // ❌
```

## Sharing secrets

- **SOPS + age** (recommended): commit `secrets/*.enc.json`; each member manages their decryption key; CI holds `AGE_SECRET_KEY` in GitHub Secrets.
- **GitHub Secrets / Variables**: runtime API keys → Secrets; non-sensitive config → Variables.

## Required env var check at startup

```ts
const requiredEnvVars = ['JWT_SECRET', 'RESEND_API_KEY', 'CLOUDFLARE_API_TOKEN'];
for (const name of requiredEnvVars) {
  if (!process.env[name]) throw new Error(`Environment variable ${name} is not set`);
}
```

## Masking conversational logs

```bash
echo "$content" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/mask-secrets.sh" > docs/talk/01.md
```

## Done

- [ ] `grep -rE 'JWT_SECRET\s*=\s*["\x27]' src/` finds nothing
- [ ] `.env` in `.gitignore`; only `.env.example` committed
- [ ] Pre-commit passes gitleaks + forbidden-patterns
- [ ] CI runs `bash .my-harness/scripts/check-forbidden-patterns.sh`
