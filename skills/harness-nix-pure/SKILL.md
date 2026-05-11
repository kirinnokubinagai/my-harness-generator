---
name: harness-nix-pure
description: Enforces a fully pure environment via Nix flake. Prohibits impure execution (brew install, global npm, etc.). Requires automatic shell activation via direnv. Fires when the user says "run a command", "install a tool", "set up the environment", or similar.
---

# harness-nix-pure

Single source of truth: `<root>/dev/.my-harness/rules/nix-pure.md` (mirrored from `${CLAUDE_PLUGIN_ROOT}/rules/nix-pure.md`).

Read `$RULES/nix-pure.md` and follow it. Same file auto-attached to Codex via `codex-ask.sh --role engineer` / `--role harness-reviewer`.
