---
name: harness-codex-consult
description: Bridge for getting a second opinion from Codex (OpenAI). Wraps codex-ask.sh so role, context, and session can be passed concisely. Fires when the user says "ask Codex", "second opinion", "review with Codex", "generate an image", or similar.
---

# harness-codex-consult

A skill that runs Claude → Codex (external LLM) conversations via the `codex-ask.sh` wrapper shell.

## Prerequisites

- `${CLAUDE_PLUGIN_ROOT:-/my-harness-generator}/scripts/codex-ask.sh` is executable
- `codex` CLI is installed and `codex login` has been run (verify with `check-codex-auth.sh`)
- `<root>/.my-harness/.config` has `USE_CODEX=yes`

## Standard invocation

```bash
${CLAUDE_PLUGIN_ROOT:-/my-harness-generator}/scripts/codex-ask.sh \
  --role <role> \
  --out <root>/.my-harness/codex-<topic>.md \
  --log <root>/.my-harness/codex.jsonl \
  "Question body (multi-line OK, heredoc OK)"
```

If the project root is registered in `~/.codex-active-session`, the session **auto-resumes**.
If `--set-active <root>` was already run during `/my-harness-init` setup, no extra setup is needed.

## Choosing a role

| Situation | role |
|-----------|------|
| Challenge assumptions, generate counter-hypotheses | `critic` |
| Detect ambiguity or contradictions in requirements | `analyst` |
| Sequence tasks, clarify dependencies and risks | `planner` |
| Validate design, analyze tradeoffs | `architect` |
| Design proposals / image generation | `designer` |
| Logic review of spec documents | `code-reviewer` |
| Security perspective | `security-reviewer` |
| TDD coaching | `tdd` |

## Examples

### Spec review
```bash
codex-ask.sh \
  --role code-reviewer \
  --context dev/docs/spec/01-problem.md dev/docs/spec/02-personas.md -- \
  "Point out logical contradictions in the spec and any mismatches between features and the technical design."
```

### Image generation (plain conversational request is enough)
```bash
codex-ask.sh \
  --role designer \
  "Generate 3 logo concepts for the todo-app, each as a PNG saved at:
- dev/docs/design/logo-1.png
- dev/docs/design/logo-2.png
- dev/docs/design/logo-3.png
Style: trustworthy, simple, warm. Primary color: #14b8a6"
```

If Codex has an image generation tool available, it will create and save the files directly.

### Architecture validation
```bash
codex-ask.sh \
  --role architect \
  --out dev/docs/spec/codex-arch-review.md \
  "For a project with user authentication + billing + Resend email
using Hono + Cloudflare D1 + Drizzle,
what is a sensible way to draw the module boundaries?"
```

## Session control

```bash
codex-ask.sh --set-active <project-root>     # Register active project
codex-ask.sh --clear-active                  # Clear registration
codex-ask.sh --session brainstorm "..."      # Named session
codex-ask.sh --session brainstorm --reset-session  # Destroy named session
```

## Failure handling

- Codex not installed → exit 127; guide user to `npm i -g @openai/codex`
- Not logged in → run `bash ${CLAUDE_PLUGIN_ROOT:-/my-harness-generator}/scripts/check-codex-auth.sh` to diagnose; prompt `codex login`
- Session expired → recreate with `--reset-session`

## Best practices

- One concern per turn — don't pile multiple questions into one call
- Attach relevant files via `--context` (no zip needed; the shell includes them as strings)
- Save output with `--out` and re-read the file — more reliable than capturing stdout
- Image generation is just a plain conversational request (no special `--image` flag needed)
