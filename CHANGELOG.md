# Changelog

All notable changes documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [4.5.0] — 2026-05-11

### Refactor — semantic-preserving prose compression

Rewrote the high-context-frequency files (agents/* loaded as system prompt every spawn, SKILL.md held in lead context for the whole session, rules/* re-read per ASSIGNMENT) to cut prose redundancy while keeping every rule, example, command, and status value. Token footprint per harness session drops noticeably.

Line counts (high-priority files only):

| File | Before | After | Δ |
|---|---:|---:|---:|
| `agents/harness-analyst.md` | 306 | 247 | -59 |
| `agents/harness-engineer.md` | 156 | 103 | -53 |
| `agents/harness-reviewer.md` | 186 | 144 | -42 |
| `agents/harness-e2e-reviewer.md` | 109 | 93 | -16 |
| `skills/harness-team-lead/SKILL.md` | 305 | 271 | -34 |
| `rules/jsdoc.md` | 87 | 65 | -22 |
| `rules/drizzle.md` | 83 | 64 | -19 |
| `rules/no-hardcoded-secrets.md` | 83 | 65 | -18 |
| `rules/design.md` | 69 | 46 | -23 |
| **Total** | **1560** | **1274** | **-286 (-18%)** |

No rule body changed. No status enum changed. No bash command changed.

## [4.4.0] — 2026-05-11

### Unified `/my-harness-adopt` and dropped 8 thin-wrapper rule skills

- `/my-harness-update` is folded into `/my-harness-adopt`. The adopt skill now branches on whether `.bare/` already exists: first-run does the destructive conversion, subsequent runs are non-destructive refreshes (rsync `dev/.my-harness/` from the latest plugin, regenerate `dev/CLAUDE.md` / `dev/AGENTS.md`, append new config flags with safe defaults). One command, two paths.
- Removed 8 thin-wrapper rule skills: `harness-tdd`, `harness-jsdoc`, `harness-hono-clean-arch`, `harness-drizzle-rules`, `harness-design-rules`, `harness-nix-pure`, `harness-no-hardcoded-secrets`, `harness-git-discipline`. The actual rule bodies live in `rules/*.md` (Single Source of Truth) and are loaded by four existing paths anyway: `dev/CLAUDE.md` (Claude Code), `dev/AGENTS.md` (Codex / Cursor / Aider), the agents' Conventions sections (Read directly), and `codex-ask.sh --role` (`--context` auto-attach). The wrapper skills were a fifth path that nobody invoked.

### Why

Skill surface is part of the API: every wrapper is a name users have to remember and we have to maintain. 4.3.0 already showed how much could be removed by deleting unused helpers; 4.4.0 follows the same logic on slash commands and rule skills.

## [4.3.0] — 2026-05-11

### Refactor — drop unused scripts / skills / templates and tighten docs

Removed (none of these had a live caller in the dispatch path):

- `scripts/anonymize-pii.sh`, `scripts/anonymize-pii-d1.sh`, `scripts/init-project.sh`, `scripts/install-rtk.sh`, `scripts/migrate-after-restore.sh`, `scripts/new-feature.sh`, `scripts/new-hotfix.sh`, `scripts/resolve-conflict.sh`, `scripts/sync-features-with-dev.sh`, `scripts/check-migration-conflict.sh`.
- `skills/harness-new-feature`, `skills/harness-new-hotfix`, `skills/harness-sync-features`, `skills/harness-resolve-conflict`, `skills/harness-codex-consult`, `skills/harness-mask` (all thin wrappers around the deleted scripts or features already covered by `harness-team-lead` / `codex-ask.sh` / `codex-exec.sh`).
- `templates/github/workflows/scheduled-db-backup.yml` (niche backup workflow that didn't justify maintenance).

Also stripped all `# >>> TEST-LOG (REMOVE AFTER DEBUGGING)` blocks from 6 files — the temporary TEST-LOG mechanism was superseded by 4.1.0's `agent-log.sh` + `monitor-agents.sh`. `.pnpm-store/` added to `.gitignore`. CHANGELOG collapsed (pre-4.0 history now a one-line summary table). README and `plugin.json` / `marketplace.json` `description` rewritten to reflect the 4.x architecture.

## [4.2.0] — 2026-05-11

`/my-harness-update` skill — refresh an already-adopted project with the latest plugin assets. Idempotent counterpart to `/my-harness-adopt` (one-shot). Re-runs `bootstrap.sh --config` against the existing `.my-harness/.config`; rsync-overwrites `dev/.my-harness/` from the plugin's current contents; regenerates `dev/CLAUDE.md` / `dev/AGENTS.md`; appends new config flags with safe defaults. `.bare/` / worktrees / commit history / code are NOT touched.

## [4.1.0] — 2026-05-11

Observability + auto-intervention:

- `scripts/agent-log.sh` — every teammate writes one line per status boundary to `<root>/.my-harness/logs/agents.log` and `agent-<name>.log`.
- `scripts/monitor-agents.sh` — view mode (live table) + `--watchdog` mode (classifies anomalies and appends JSONL to `anomalies.jsonl`).
- Anomaly kinds: `stagnation`, `repeated-blocked`, `codex-exec-failure`, `codex-no-op`, `suffixed-name`.
- `SKILL.md` Step 3.0 — the lead reads new anomalies at the top of every dispatch iteration and applies a deterministic intervention table (PING / escalate / fall back from Codex / redo / halt).

Also fixed: BSD `date -j -f` was parsing ISO-8601 in the local TZ silently — switched to `-ujf` for UTC parse, and the awk window-filter now compares ISO-8601 strings lexicographically.

## [4.0.0] — 2026-05-11 (BREAKING)

True Codex delegation. All four lane roles can individually delegate to Codex:

- `scripts/codex-exec.sh` (new) wraps `codex exec --cd <worktree> --sandbox <mode> --ask-for-approval never` so Codex performs real file edits (engineer: `workspace-write`) or reads the worktree freely for review (reviewer: `read-only`). engineer-N / reviewer-N (Claude) become monitors.
- `analyst` gains `USE_CODEX_ANALYST` (new flag in `bootstrap.sh`). When set, brief / commit message / PR body text generation goes through `codex-ask.sh --role harness-analyst`. git operations stay on Claude.
- `codex-ask.sh` gets a `harness-analyst` role (same rule auto-attach as engineer / harness-reviewer).
- New status values: `blocked-codex-error` (non-auth failures from `codex exec`).

BREAKING: engineer / reviewer Codex flows no longer return ready-to-paste text. Codex now edits the worktree directly; consumers that read `codex-eng-<#>.md` for code text should inspect the worktree diff instead.

## Pre-4.0 history (summary)

| Version | Highlight |
|---|---|
| 3.10.0 | `rules/` became the single source of truth shared across Claude and Codex; bootstrap generates `dev/CLAUDE.md` and `dev/AGENTS.md` (regular file copy, no symlink) pointing at `rules/*.md`; `codex-ask.sh` auto-attaches the same rule files via `--context`. |
| 3.9.4 | `codex-ask.sh` path absolutised in all 3 agents — relative path was unreachable inside lane worktrees. |
| 3.9.3 | `owned_files` clarified as a dispatch-time hint, NOT an in-lane whitelist. |
| 3.9.2 | engineer hard rules: run `pnpm install` exactly as shown; new `blocked-workspace-not-ready` status. |
| 3.9.1 | Drop generated `start-dev.sh` launcher; completion banners print `cd <root>/dev && claude` directly. |
| 3.9.0 | `/my-harness-adopt` — convert an existing git repo into the harness layout while preserving history. |
| 3.8.5 | analyst commit gate (Step 5 locked behind e2e+reviewer pass); engineer no-git hard rule restated; already-running teammate phrasing. |
| 3.8.4 | Propagate `root` from analyst → engineer / e2e-reviewer / reviewer so `USE_CODEX_*` resolves. |
| 3.8.3 | Parallel dispatch: spawn sequential, `ASSIGNMENT` non-blocking, refill freed lanes immediately. |
| 3.8.2 | Drop project-root devshell warmup; new "Output discipline" rule (no narration / no cat). |
| 3.8.1 | Resolve `ROOT` to project root from any cwd (`__resolve_project_root` in every script). |
| 3.8.0 | Lane-by-lane spawn gate (`spawn-lane-decision.sh`) + name-collision guard + vendor-neutral cleanup (dropped vendor-specific env-var wrangling and third-party MCP enumeration). |
| 3.0 – 3.7 | Iterative work on the kernel-panic-prevention path (preflight gate, lane-lock, devshell wrapper, content-hash cache, task lifecycle, worktree management). Largely subsumed by 3.8+ rewrites. |
| 2.x | Switched to Agent Teams architecture (16 persistent teammates); shared Codex daemon; Cloudflare IaC moved from OpenTofu to Alchemy v2. |
| 1.0.0 | Initial plugin release: skills + agents + hooks + secret masking. |
