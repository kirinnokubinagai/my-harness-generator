---
name: harness-jsdoc
description: Requires JSDoc / TSDoc on every variable, constant, function, and type. Prohibits inline comments inside function bodies. All descriptions must be written in the project language (LANG from .my-harness/.config, default en). Fires when the user says "write a function", "add a comment", "type definition", "write a description", or similar.
---

# harness-jsdoc

Single source of truth: `<root>/dev/.my-harness/rules/jsdoc.md` (mirrored from `${CLAUDE_PLUGIN_ROOT}/rules/jsdoc.md`).

Read `$RULES/jsdoc.md` and follow it. Same file auto-attached to Codex via `codex-ask.sh --role engineer` / `--role harness-reviewer`.
