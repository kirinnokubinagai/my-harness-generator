---
name: harness-check-codex-auth
description: Checks whether the Codex CLI is installed and authenticated. Wraps `check-codex-auth.sh`. Fires when the user asks "can I use Codex", "codex login", "Codex authentication", or similar.
---

# harness-check-codex-auth

Determines whether the Codex CLI (`@openai/codex`) is ready to use. Run this during `/my-harness-init` setup phase 0, or before starting any Codex integration.

## Invocation

```bash
bash ${CLAUDE_PLUGIN_ROOT:-/my-harness-generator}/scripts/check-codex-auth.sh
```

## Results

| stdout | exit code | Meaning | Action |
|--------|-----------|---------|--------|
| `logged-in` | 0 | OK — `codex exec` will work | Continue |
| `not-logged-in` | 1 | CLI is installed but not authenticated | Guide user to run `codex login` |
| `not-installed` | 127 | CLI is not installed | Guide user to run `npm i -g @openai/codex` |

## Detection logic

- Checks CLI existence with `command -v codex`
- Checks for `~/.codex/auth.json`
- Uses jq to verify that at least one of `tokens.access_token`, `tokens.id_token`, or `api_key` is non-empty

## Guidance templates

`not-installed`:
```
Codex CLI not found. Please run:
  npm install -g @openai/codex
  codex login
```

`not-logged-in`:
```
Codex CLI is installed but not authenticated. Please run:
  codex login
Then try again.
```

## Related

- Consulting Codex: `harness-codex-consult`
- This skill is called automatically when the user selects USE_CODEX=yes during `/my-harness-init` setup
