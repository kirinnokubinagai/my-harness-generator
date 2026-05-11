---
name: harness-drizzle-rules
description: Enforces Drizzle ORM + Cloudflare D1 conventions. Only drizzle-kit migrate is allowed; push is prohibited; migration naming and ordering are guaranteed. Fires when the user mentions "change DB schema", "migration", "add a table", or similar.
---

# harness-drizzle-rules

Single source of truth: `<root>/dev/.my-harness/rules/drizzle.md` (mirrored from `${CLAUDE_PLUGIN_ROOT}/rules/drizzle.md`).

Read `$RULES/drizzle.md` and follow it. Same file auto-attached to Codex via `codex-ask.sh --role engineer` / `--role harness-reviewer`.
