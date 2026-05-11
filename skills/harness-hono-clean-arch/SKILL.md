---
name: harness-hono-clean-arch
description: Enforces Clean Architecture on Hono backends. Mandates 4-layer separation (domain / application / infrastructure / interfaces) and strict dependency direction rules. Fires when the user says "write a Hono API", "add a handler", "implement a use case", "write a repository", or similar.
---

# harness-hono-clean-arch

Single source of truth: `<root>/dev/.my-harness/rules/hono-clean-arch.md` (mirrored from `${CLAUDE_PLUGIN_ROOT}/rules/hono-clean-arch.md`).

Read `$RULES/hono-clean-arch.md` and follow it. Same file auto-attached to Codex via `codex-ask.sh --role engineer` / `--role harness-reviewer`.
