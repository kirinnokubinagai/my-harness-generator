---
name: harness-no-hardcoded-secrets
description: Absolutely prohibits hardcoding secret values, API keys, and connection strings. Only environment variables, SOPS encryption, and Secrets Manager are allowed. Pre-commit mechanically blocks violations. Fires when the user mentions "environment variable", "API key", "DATABASE_URL", "secret key", ".env", or similar.
---

# harness-no-hardcoded-secrets

Single source of truth: `<root>/dev/.my-harness/rules/no-hardcoded-secrets.md` (mirrored from `${CLAUDE_PLUGIN_ROOT}/rules/no-hardcoded-secrets.md`).

Read `$RULES/no-hardcoded-secrets.md` and follow it. Same file auto-attached to Codex via `codex-ask.sh --role engineer` / `--role harness-reviewer`.
