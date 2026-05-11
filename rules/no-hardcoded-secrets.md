# No hardcoded secrets

No hardcoded secrets in any code, config, or commit.

## Rules

| Type | Hardcoding |
|---|---|
| API keys (`sk-...`, `ghp_...`, `xoxb-...`, etc.) | **Prohibited** |
| Values that should be env vars (`JWT_SECRET`, `DATABASE_URL`, etc.) | **Prohibited** |
| Credentials in URLs (`https://user:pass@host`) | **Prohibited** |
| Production DSNs (`postgres://prod...`) | **Prohibited** |
| Plaintext `.env` committed | **Prohibited** (`.env.example` only) |
| PEM private keys | **Prohibited** |

Pre-commit blocks slip-throughs:
- `.gitleaks.toml` + `gitleaks protect`
- `check-forbidden-patterns.sh` (custom patterns)

## Allowed

```ts
// Environment variable
const jwtSecret = process.env.JWT_SECRET ?? (() => {
  throw new Error('JWT_SECRET is not set');
})();

// Cloudflare Workers binding
export default {
  async fetch(request, env) {
    const apiKey = env.RESEND_API_KEY;  // bound in wrangler.toml
  }
};

// SOPS decryption
const { OPENAI_API_KEY } = JSON.parse(
  await sopsDecrypt('secrets/openai.enc.json')
);
```

## Prohibited

```ts
const JWT_SECRET = "abc12345abcdefghijk";          // ❌
const DATABASE_URL = "postgres://user:pass@prod.db.example.com/app";  // ❌
fetch("https://admin:s3cret@api.example.com/x");   // ❌
// Adding plaintext .env to tracked files          // ❌
```

## Sharing secrets across the team

### SOPS + age (recommended)
- Commit the encrypted file `secrets/cloudflare.enc.json` to git.
- Each member manages their decryption key (1Password / iCloud Keychain).
- CI holds `AGE_SECRET_KEY` in GitHub Secrets.

### GitHub Secrets / Variables
- Runtime API keys → Secrets.
- Non-sensitive config → Variables.

## Required env var check at startup

```ts
const requiredEnvVars = ['JWT_SECRET', 'RESEND_API_KEY', 'CLOUDFLARE_API_TOKEN'];
for (const name of requiredEnvVars) {
  if (!process.env[name]) {
    throw new Error(`Environment variable ${name} is not set`);
  }
}
```

## Masking conversational logs

```bash
echo "$content" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/mask-secrets.sh" > docs/talk/01.md
```

## Done

- [ ] `grep -rE 'JWT_SECRET\s*=\s*["\x27]' src/` finds nothing.
- [ ] `.env` is in `.gitignore`; only `.env.example` is committed.
- [ ] Pre-commit passed gitleaks + forbidden-patterns.
- [ ] CI runs `bash .my-harness/scripts/check-forbidden-patterns.sh`.
