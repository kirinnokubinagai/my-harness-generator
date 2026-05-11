---
name: harness-tdd
description: Enforces test-driven development (TDD). Must be applied before implementing new features, fixing bugs, refactoring, or changing behavior. Ensures the Red-Green-Refactor cycle is followed and no production code is written without a failing test. Fires when the user says "write a test", "do TDD", "before implementing", "fix a bug", or similar.
---

# harness-tdd

Single source of truth: `<root>/dev/.my-harness/rules/tdd.md` (mirrored from `${CLAUDE_PLUGIN_ROOT}/rules/tdd.md`).

```bash
RULES="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}/rules"
# Or, when working inside a harness project:
#   RULES="$ROOT/dev/.my-harness/rules"
```

Read `$RULES/tdd.md` and follow it.

The same file is auto-attached to Codex via `codex-ask.sh --role engineer` (and `--role harness-reviewer`), so Claude and Codex apply identical TDD discipline.
