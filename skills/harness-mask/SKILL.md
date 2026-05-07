---
name: harness-mask
description: Replaces secret values (API keys / email / phone / URL credentials / card numbers / JWTs / PEM keys, etc.) with <MASKED:type> placeholders. Must be applied before writing to docs/talk or docs/spec, and before displaying logs. Fires when the user says "mask secrets", "hide sensitive information", or similar.
---

# harness-mask

A skill that mechanically masks secret values to prevent leakage when writing files or displaying output.
The `UserPromptSubmit` hook applies this automatically, but there are situations where Claude must call it **explicitly**.

## Situations that always require masking

| Situation | Action |
|-----------|--------|
| Writing to `docs/talk/*.md` | Pipe through mask |
| Writing to `docs/spec/*.md` | Pipe through mask |
| Before passing context files to Codex | Run mask |
| Before pasting into issue / PR descriptions | Run mask |
| Long logs displayed to the user | Run mask |

## How to call it

### Via stdin
```bash
echo "$user_response" | bash ${CLAUDE_PLUGIN_ROOT:-/my-harness-generator}/scripts/mask-secrets.sh >> dev/docs/talk/01-problem.md
```

### Via file
```bash
bash ${CLAUDE_PLUGIN_ROOT:-/my-harness-generator}/scripts/mask-secrets.sh /tmp/raw.md > dev/docs/spec/01-problem.md
```

### Overwrite-mask an existing file
```bash
TMP=$(mktemp)
bash ${CLAUDE_PLUGIN_ROOT:-/my-harness-generator}/scripts/mask-secrets.sh existing.md > "$TMP"
mv "$TMP" existing.md
```

## What gets masked (9 types)

| Input example | Output |
|---------------|--------|
| `sk-ant-abcd1234...` | `<MASKED:api-key>` |
| `ghp_abcdef...` | `<MASKED:api-key>` |
| `xoxb-...` / `xoxp-...` | `<MASKED:api-key>` |
| `sk_live_...` | `<MASKED:api-key>` |
| `AKIA...` | `<MASKED:aws-key>` |
| `eyJ...eyJ...sig` | `<MASKED:jwt>` |
| `https://user:pass@host` | `<MASKED:url-cred>@host` |
| `user@example.com` | `<MASKED:email>` |
| `09012345678` | `<MASKED:phone>` |
| `4111-1111-1111-1111` | `<MASKED:cc>` |
| `-----BEGIN PRIVATE KEY-----...` | `<MASKED:private-key>` |
| `JWT_SECRET=xxx` format | `JWT_SECRET=<MASKED:secret>` |
| GCP service_account JSON | `<MASKED:gcp-sa>` |

## Double-defense structure

```
[User input] → [UserPromptSubmit hook] → auto mask → docs/talk/<date>.md
                                               ↓
                                          git commit
                                               ↓
                              [pre-commit] → gitleaks + forbidden-patterns re-check
                                               ↓
                                          push (blocked here if anything slipped through)
```

Claude calling this explicitly is a safety net for paths that bypass the hook (e.g. writing to docs/spec/ directly with the Write tool).

## False positive note

- Example: a test dummy address `test@example.com` will be masked
- If this is a problem, write directly without running `harness-mask` (confirm with the user first)
- Sample values in `.env.example` are also masked, but that is the safe-side outcome

## Checklist

- [ ] Writes to docs/talk went through mask-secrets.sh
- [ ] Writes to docs/spec went through mask-secrets.sh
- [ ] Files passed to Codex went through mask-secrets.sh
- [ ] gitleaks runs as a second layer of defense in pre-commit
