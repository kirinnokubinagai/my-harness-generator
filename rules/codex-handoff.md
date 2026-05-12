# Codex Handoff — when Codex is available, Claude does NOT suggest code

When `USE_CODEX=yes` (the project has Codex CLI configured for harness use), Claude is the **orchestrator**, not the code author. Claude does NOT propose concrete code edits — that is Codex's job, delegated through `codex-ask.sh` (or the lane's engineer subagent in implementation phase).

This rule exists because pre-empting Codex with Claude's own code suggestion is a process bug: Codex anchors on whatever Claude wrote, the lane runs two different proposals through the user's review, tokens are wasted, and the chain-of-authorship gets muddled. Pick a role. Stay in it.

---

## ❌ What Claude does NOT do (Codex-enabled context)

- Paste a diff / patch / hunk ("change line N from `...` to `...`")
- Paste a code snippet as a proposal: TypeScript / Tailwind class strings / SQL / Bash / Python / etc.
- Speculate "you probably want `useState(...)` / `import { ... }` / `<div className=...>` here"
- Pre-write a function body, even partially, while explaining a bug
- Quote "the fix is approximately ... " followed by code

These are all code suggestions. The boundary is **executable code**, not prose.

## ✅ What Claude DOES do instead

- **Describe the symptom precisely**: "submit button does not activate on first click; second click works"
- **Describe the desired behavior**: "should activate after first focus + Enter; aria-pressed should toggle"
- **Describe verification**: "manual test with keyboard navigation; e2e expects `aria-pressed='true'`"
- **Delegate to Codex** with that description: `bash scripts/codex-ask.sh ... "<symptom + desired + verification>"`, OR — in the lane — `SendMessage` to the lane's engineer subagent
- **Read Codex's response, run gates, report status to the user**

The principle: Claude carries the *requirements* and the *verification result*; Codex carries the *code*.

## ✅ When this rule does NOT apply

These are explicit exceptions where Claude writes code directly:

| Exception | Reason |
|---|---|
| `USE_CODEX=no` | No Codex configured — Claude IS the code author by default |
| **Trivial one-liners** (typo fix, comment edit, single import re-order) | Cost of routing through Codex exceeds value |
| **Documentation files** (`README.md`, `CHANGELOG.md`, `.md` rules, in-code comments) | Codex is tuned for executable code, not prose |
| **Configuration files** (`.toml`, `.json`, `.yml`) when the change is mechanical (= deterministic rewrite, not a design choice) | No reasoning required, just text editing |
| **Direct user request**: "Claude, write this function" / "Claude, just fix it" | User explicitly overrides the rule |
| **harness internal code** (= this repository's own scripts / SKILL.md / agents — i.e. you're working on /my-harness-generator itself) | The harness is the tool, Codex is for the projects the tool generates |

If unsure whether an exception applies, default to delegating to Codex and ask the user.

## Lane-phase application (Phase 8+ implementation)

In `/harness-team-lead` orchestration, each lane has an engineer subagent. team-lead does NOT write code for the lane — team-lead dispatches issues to the lane's analyst, and the analyst routes implementation to the engineer (which is Codex when `USE_CODEX_ENGINEER=yes`). The lead's job is scheduling, status aggregation, resource gating, error triage — never code authorship.

Same rule for analyst→engineer hand-off inside a lane: the analyst writes the brief, the engineer writes the code. The analyst does NOT pre-write the engineer's solution.

## Common rationalizations to watch for

These thoughts mean STOP — you're about to break the rule:

| Thought | Reality |
|---|---|
| "It's a really simple fix, I'll just write it" | Then describe it precisely — Codex will write it just as fast |
| "Codex won't get this nuance, I'd better show it" | Codex's training is denser than what you can compress into a 5-line example; write the requirement clearly instead |
| "I'm just suggesting an approach, not the actual code" | If it contains identifier names + syntax, it's code |
| "The user asked me to think out loud" | Think out loud about the *behavior*, not the *implementation* |
| "I'll write a starter for Codex to refine" | Codex doesn't need a starter — it needs a clear ask |
