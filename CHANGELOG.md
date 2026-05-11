# Changelog

All notable changes to this plugin documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [4.1.0] — 2026-05-11

### Added — observability + auto-intervention

- `scripts/agent-log.sh` — single-line append helper used by every teammate at every status boundary (spawn ack, ASSIGNMENT received, codex start/done, gate results, blocked-*, pr-created, cleared). Writes to `<root>/.my-harness/logs/agents.log` and `<root>/.my-harness/logs/agent-<name>.log`.
- `scripts/monitor-agents.sh` — two modes:
  - **View mode** (default): live status table refreshed every N seconds. Run in a second terminal next to `/harness-team-lead`.
  - **Watchdog mode** (`--watchdog`): scans `agents.log` every 30 s, classifies anomalies (`stagnation`, `repeated-blocked`, `codex-exec-failure`, `codex-no-op`, `suffixed-name`) and appends them as JSONL to `<root>/.my-harness/logs/anomalies.jsonl`.
- `agents/harness-{analyst,engineer,e2e-reviewer,reviewer}.md` gain an `Observability` section listing the minimum log lines they must emit at each step.
- `skills/harness-team-lead/SKILL.md` gets a new Step 3.0 "Anomaly check" that runs before every dispatch iteration. The lead reads new anomalies from `anomalies.jsonl` and applies a deterministic intervention table (PING stagnation, escalate repeated blocks, fall back from Codex on consecutive failures, ask engineer to redo on codex-no-op, halt on suffix corruption).

### Usage

```bash
# In a second terminal next to /harness-team-lead:
bash <plugin>/scripts/monitor-agents.sh /path/to/project                  # live view
bash <plugin>/scripts/monitor-agents.sh /path/to/project --watchdog &     # background watchdog
```

The view shows per-lane status + the last 10 events. The watchdog writes anomalies that the lead consumes automatically.

## [4.0.0] — 2026-05-11 (BREAKING)

### Added — true Codex delegation via `codex exec`

- New `scripts/codex-exec.sh` wraps `codex exec --cd <worktree> --sandbox <mode> --ask-for-approval never`. Used when the role's job is to actually edit / read worktree files (engineer, reviewer), not just generate text.
- `agents/harness-engineer.md` Codex mode rewritten: when `USE_CODEX_ENGINEER=yes`, Codex performs file edits in the worktree (`sandbox=workspace-write`). engineer-N (Claude) becomes a monitor — verifies `git diff`, runs gates, reports.
- `agents/harness-reviewer.md` Codex mode rewritten: when `USE_CODEX_REVIEWER=yes`, Codex reads the worktree freely (`sandbox=read-only`) and emits PASS or file:line violations. reviewer-N (Claude) forwards the report.
- `agents/harness-analyst.md` gains a Codex mode: when `USE_CODEX_ANALYST=yes`, the brief / commit message / PR body text generation is delegated to Codex via `codex-ask.sh --role harness-analyst` (text-only, since analyst doesn't edit code). Step 1 starts a session, Step 5 resumes it so the brief context is preserved.
- New `USE_CODEX_ANALYST` config flag in `bootstrap.sh` (default `y` when `USE_CODEX=yes`). All four lane roles (analyst / engineer / e2e-reviewer / reviewer) can now individually delegate to Codex.
- New `harness-analyst` role in `scripts/codex-ask.sh` (auto-attaches the same 7 rule files as engineer / harness-reviewer).
- New status values: `blocked-codex-error` (non-auth failures from `codex exec`).

### Why BREAKING

The engineer / reviewer Codex flows are no longer "Codex returns text → Claude edits the files". They become "Codex edits the files → Claude verifies". Existing custom integrations that assumed `$ROOT/.my-harness/codex-eng-<issue#>.md` contained ready-to-paste code text now find a `.log` of Codex's stdout (which mostly summarises what it did, since the actual change is on disk).

Existing `.my-harness/.config` files without `USE_CODEX_ANALYST` default to `no` — safe fallback. Re-run `bootstrap.sh --config .my-harness/.config` interactively or set the flag manually to opt in.

## [3.10.0] — 2026-05-11

### Added — single source of truth for harness rules, shared across Claude Code and Codex CLI

- New `rules/` directory at the plugin root holding 7 rule files (`tdd.md`, `jsdoc.md`, `hono-clean-arch.md`, `drizzle.md`, `design.md`, `nix-pure.md`, `no-hardcoded-secrets.md`). Plain Markdown, no agent-specific syntax.
- New `templates/CLAUDE.md.tmpl`: bootstrap renders this into `<root>/dev/CLAUDE.md` and copies it verbatim to `<root>/dev/AGENTS.md`. Both files point at `.my-harness/rules/*.md` so Claude Code, Codex CLI standalone, Cursor, Aider — anything that follows AGENTS.md or CLAUDE.md — picks up identical rules.
- `bootstrap.sh` step 5a now generates `dev/CLAUDE.md` and `dev/AGENTS.md` (regular file copy, not a symlink, by request).
- `scripts/codex-ask.sh` `--role engineer` and `--role harness-reviewer` now auto-attach the same 7 rule files via `--context` (resolved from `<root>/dev/.my-harness/rules/` or, as a fallback, `${CLAUDE_PLUGIN_ROOT}/rules/`). The previous hardcoded multi-clause prefix string is replaced with a short pointer so the rule body lives in exactly one place.
- `agents/harness-engineer.md` and `agents/harness-reviewer.md` Conventions sections now Read the rule files directly instead of loading the legacy skills via the Skill tool.

### Changed — `skills/harness-{tdd,jsdoc,hono-clean-arch,drizzle-rules,design-rules,nix-pure,no-hardcoded-secrets}` are thin pointers

- The 7 convention skills are now ~10 lines each. The body simply tells the reader to load `<root>/dev/.my-harness/rules/<name>.md` (or `${CLAUDE_PLUGIN_ROOT}/rules/<name>.md`). Keeps slash-command compatibility (`/oh-my-claudecode:harness-tdd` etc. still works) without duplicating the rule text.
- Total skill lines for these 7 files dropped from 762 to 78.

### Why

Previously, the engineer rule body was duplicated in `scripts/codex-ask.sh` (hardcoded role prefix) AND in seven `skills/harness-*/SKILL.md` files. Updating one and forgetting the other produced subtly different behaviour between Claude turns and Codex turns. The single source of truth removes that drift entirely; both clients now read the same on-disk Markdown.

## [3.9.4] — 2026-05-11

- engineer / e2e-reviewer / reviewer now invoke `codex-ask.sh` via the absolute path `${CLAUDE_PLUGIN_ROOT}/scripts/codex-ask.sh`. The previous relative path `scripts/codex-ask.sh` did not exist inside the lane worktree, so every Codex call silently failed and the teammate fell back to Claude (or stalled in "blocker waiting"). Fixes Codex delegation never running even with `USE_CODEX_*=yes`.

## [3.9.3] — 2026-05-11

- Clarify `owned_files` semantics: it is a dispatch-time lane-collision hint, NOT an in-lane file whitelist. engineer-N may freely touch any file the brief's Goal requires (including shared config like `biome.json`, `package.json`, `pnpm-workspace.yaml`) without escalating to analyst-N. analyst-N only escalates to team-lead when the file in question is also listed as `owned_files` of another currently-active lane. Fixes lanes stalling because they treated `owned_files` as a hard whitelist.

## [3.9.2] — 2026-05-11

- engineer hard rules: `pnpm install` is run exactly as shown — no `--ignore-workspace`, no improvised `--frozen-lockfile`, no side-install into a sub-package to "avoid workspace conflicts" (lane-lock already serialises). `--frozen-lockfile` is install-only and must never be passed to `pnpm add`.
- New status `blocked-workspace-not-ready`: when the monorepo skeleton is missing (no top-level `package.json`, `pnpm-workspace.yaml`, or referenced package directory), engineer stops and reports rather than improvising. analyst forwards to team-lead, team-lead pauses the lane and surfaces the blocking dependency to the user.

## [3.9.1] — 2026-05-11

- `bootstrap.sh` no longer generates `<root>/start-dev.sh`. The launcher script was a thin wrapper around `cd <root>/dev && claude`, and several users preferred not having an extra file at the project root. All completion banners (`bootstrap.sh`, `/my-harness-init` Phase 8.6, `/my-harness-adopt` Step 4) and READMEs now print the manual command directly.

## [3.9.0] — 2026-05-10

- New `/my-harness-adopt` skill + `scripts/adopt-existing.sh`. Converts an existing git repo at `$(pwd)` into the harness layout (`.bare/` + `main/` `stage/` `dev/` worktrees + `dev/.my-harness/`) while preserving commit history. Backs up the original `.git/` to `<root>/.my-harness-backup/<ts>/git/` for rollback.
- Asks a minimal subset of the `/my-harness-init` Setup questions (project name, lang, Codex flags, Playwright/Maestro, GitHub Issues, global CLAUDE.md), writes `.my-harness/.config`, then runs the existing `bootstrap.sh --config` to install hooks / `dev/.claude/settings.json`.

## [3.8.5] — 2026-05-10

- analyst hard rule: never `git commit` / `git push` / `gh pr create` until BOTH `[e2e-reviewer-N status=pass]` AND `[reviewer-N status=pass]` are received. Step 5 (commit + PR) is locked behind Step 4.
- engineer hard rule restated: absolutely no git operations of any kind.
- analyst now told explicitly that engineer/e2e-reviewer/reviewer are already-running teammates — talk to them with `SendMessage`, never `Agent({})`. The phrasing "起動 / spawn / launch" is forbidden.

## [3.8.4] — 2026-05-10

- analyst-N's ASSIGNMENT / TEST / REVIEW messages now carry `root: <ROOT>`. engineer-N / e2e-reviewer-N / reviewer-N bind `ROOT` from the message and read `$ROOT/.my-harness/.config` correctly.
- Fixes Codex-mode flags (`USE_CODEX_*`) being read as empty (because `$ROOT` was undefined), which silently dropped every teammate into Claude fallback even when the project was configured for Codex.

## [3.8.3] — 2026-05-10

- Step 3 rewritten so dispatch is parallel. Spawn stays sequential (one lane at a time, gated by resources), but ASSIGNMENT is sent to each lane and the lead immediately moves on to fill the next lane — no blocking on completion. Completion handling is "wait for any inbound message" and refill that lane.
- Previous 3.8.x flow blocked the lead on a single lane between dispatch and PR, defeating parallelism. Lanes now run concurrently as expected.

## [3.8.2] — 2026-05-10

- Removed Step 0.5 project-root devshell warmup. The project root holds only `.bare/` and worktrees; the `flake.nix` lives in `dev/`. Each teammate runs `build-dev-env.sh "$WORKTREE"` itself.
- Removed the duplicate ROOT normalisation block in SKILL.md. Each script normalises internally; passing `$(pwd)` is enough.
- New "Output discipline" section: no intermediate narration, no `cat` of script output, no `ls`/`echo` introspection.
- Step 1 explicitly says do not display the captured pending list.

## [3.8.1] — 2026-05-10

- Every script in `skills/harness-team-lead/scripts/` now resolves `ROOT` to the project root (the directory holding `.bare/`) regardless of cwd. Fixes `harness-worktree.sh` creating lanes under `dev/lanes/` when launched from `dev/`.
- `harness-team-lead` SKILL.md normalises `ROOT` after `preflight.sh` and includes `root: <ROOT>` in the analyst-N ASSIGNMENT.
- `agents/harness-analyst.md` binds `ROOT` from the ASSIGNMENT message instead of `$(pwd)`; reads `$ROOT/dev/docs/task/child/<id>.md` correctly when launched from `dev/`.

## [3.8.0] — 2026-05-10

- Lanes are spawned one at a time, gated by `spawn-lane-decision.sh` (resource probe + name-collision check). Empty team after `TeamCreate`.
- `Agent({name})` for an existing name is structurally prevented (gate returns `SKIP`); pre-existing `analyst-N-M` suffixes are detected as `corrupt`.
- Removed: `OMC_SKIP_HOOKS` export, MCP server enumeration in `preflight.sh`, `scripts/launch-harness.sh`, `templates/harness.mcp.json`, `lane-capacity.sh`.
- Temporary test logging in every script writes to `<ROOT>/.my-harness/logs/harness-test.log`. Removal command documented in `SKILL.md`.

## [3.5.0] — 2026-05-10

### Fixed — CRITICAL: 3.4.0 had 4 production-broken gaps (apology)

3.4.0 fixed the source/wrapper problem but shipped with the orchestration flow incomplete. Concrete gaps that would have triggered failure on the very first run:

1. **No task `status: pending → in_progress → completed` updates.** `list-pending-issues.sh` only filters by `status: pending`, so without the analyst flipping it to `in_progress` at assignment, the same task would be re-dispatched on every `/loop` wakeup — and worse, **dispatched simultaneously to multiple lanes**. Without the flip to `completed` after PR creation, the task would re-appear forever.
2. **No `git worktree add` / `worktree remove`.** team-lead Step 3c sent assignments referencing `<ROOT>/lanes/feat-<X>-<slug>/` paths but never created them; analyst-N would `cd` into a nonexistent dir.
3. **`owned_files` extraction mismatch.** SKILL.md said "from front matter when USE_GITHUB_ISSUES=no", but actual task md files put owned files in the body line `**ファイル所有**: a, b, c`. The conflict-avoidance check in Step 3b was reading from the wrong place — silently always finding nothing — meaning two lanes could grab tasks editing the same files.
4. **No `parent` task close logic.** Children would cycle through completed but the parent task md / GitHub issue would stay open forever.

3.4.0 was tested only at the `build-dev-env.sh` / wrapper layer, not the orchestration flow. **This is on me; should not have shipped.** Apologies again.

### New scripts

All shell-script-only (no agent context required), all idempotent, all CLAUDE_PLUGIN_ROOT-aware via `${VAR:?msg}` hard-fail.

- `harness-task-status.sh <root> <id> <pending|in_progress|completed>` — flip a task md's front-matter status (sed in the front-matter band only — body lines starting with `## status:` are untouched). USE_GITHUB_ISSUES=yes uses `gh issue edit/close`.
- `harness-worktree.sh <add|remove> <root> <id> <slug>` — create / destroy a lane worktree at `<root>/lanes/feat-<id>-<slug>/` with branch `feat/<id>-<slug>` off `origin/dev`. Uses explicit refspec (`+refs/heads/dev:refs/remotes/origin/dev`) so bare clones without the default fetch refspec also work. Idempotent on both add and remove.
- `harness-parent-status.sh <root> <parent-id>` — close the parent task when **all** of its children have `status: completed`. No-op while any child is still pending/in_progress. Symmetric for yes/no.
- `list-pending-issues.sh` refactored — output is now **4 tab-separated columns**: `<id>\t<lane>\t<owned_files_csv>\t<title>`. The `owned_files` field is parsed from the body line `**ファイル所有**: ...` (or English `**Owned files**:`); team-lead can use this directly for conflict avoidance with no extra parsing.

### Updated flow

- `agents/harness-analyst.md`:
  - **Step 0.5 (new)** — call `harness-task-status.sh ... in_progress` before brief production. Stops re-dispatch on `/loop` wakeup and prevents the same task being assigned to two lanes simultaneously.
  - **Step 1.1 explicit** — local task file path is `<root>/dev/docs/task/child/<id>.md`; the id matches the markdown filename. (Previously this was implied but never written.)
  - **Step 5.5 (new)** — call `harness-task-status.sh ... completed` + `harness-parent-status.sh ... <parent>` after PR creation.

- `skills/harness-team-lead/SKILL.md`:
  - **Step 1** — output format documented as 4-column TSV; explains how `status: in_progress` filters block re-dispatch.
  - **Step 3b** — preferred-lane logic: respect the task's `lane:` field; defer if that lane is busy rather than fall back to a different lane (which could cause owned-files conflicts).
  - **Step 3c** — calls `harness-worktree.sh add` before sending the assignment.
  - **Step 3e** — calls `harness-worktree.sh remove` after the post-PR clear sweep.

### Verified end-to-end (27-step test suite, all pass before commit)

```
✅ All 5 scripts executable
✅ build-dev-env wrapper still works (3.4.0 not regressed)
✅ wrapper exec pnpm
✅ wrapper from bash 3.2 → /nix/store
✅ wrapper from fish → /nix/store
✅ CLAUDE_PLUGIN_ROOT unset hard-fails
✅ task-status pending→in_progress
✅ task-status in_progress→completed
✅ task-status invalid status → exit 65
✅ task-status missing id → exit 3
✅ parent open while children pending
✅ parent closes when all children completed
✅ parent-status idempotent on already-completed
✅ list-pending: only pending tasks listed (in_progress filtered out)
✅ list-pending: 4 tab-separated columns
✅ list-pending: row content correct (id/lane/owned/title)
✅ list-pending on real todo-app: 107 rows
✅ worktree add creates dir
✅ worktree on correct branch
✅ worktree add idempotent
✅ worktree remove deletes dir
✅ worktree remove deletes branch
✅ worktree remove idempotent
```

### Migration

Existing 3.4.0 users: nothing to do; new scripts deploy alongside existing ones. The `list-pending-issues.sh` output format changed from 2 columns to 4 — if you have a custom override that consumed the old format, switch to indexing columns 1, 2, 3, 4 for id/lane/owned_files/title.

## [3.4.0] — 2026-05-10

### Fixed — CRITICAL: 3.3.0 was broken in production (apology)

3.3.0 shipped with a `source $DEV_ENV` pattern that does not work in production:

- macOS `/bin/bash` 3.2.57 cannot parse `nix print-dev-env` output (uses bash-4+ `;&` case fall-through, `declare -a` arrays). Source fails with `syntax error near unexpected token`.
- zsh accepts the parse but does not execute it as bash; the resulting PATH does not contain /nix/store paths (system pnpm/git/node remain).
- fish has its own syntax entirely.

3.3.0 was tested only against the build-dev-env.sh write path, not the actual source step. **This is on me; it should not have shipped.** Apologies.

### New — devshell wrapper, callable from any shell

build-dev-env.sh now generates a shell-agnostic wrapper at `<flake-dir>/.my-harness/devshell`. The wrapper's shebang points to nix-provided bash 5+:

```
#!/nix/store/.../bash-5.2p37/bin/bash
set -e
source <raw env file> >/dev/null 2>&1
exec "$@"
```

Callers from any shell — bash 3.2 / zsh / fish / sh — invoke `"$DEVSH" <command>` and the wrapper handles the bash-4-syntax env file internally. Verified end-to-end:

- bash 3.2 / zsh / fish all run pnpm/git/node/gh from /nix/store correctly
- shellHook side effects (PNPM_HOME, PLAYWRIGHT_BROWSERS_PATH, MAESTRO_DRIVER_STARTUP_TIMEOUT) all evaluated and exported
- Cache hit < 25 ms, cold rebuild only on flake content change (sha256 of flake.nix + flake.lock)
- Per-worktree isolation: lane-3 modifying its flake.nix does not affect lane-1/2/4

### New — Step 0 dev sync in analyst flow

When team-lead assigns an issue, analyst-N now runs `git fetch origin dev && git merge --no-ff --no-edit origin/dev` before brief production. Previously, lanes accumulated stale dev base across PR merges; now each new issue starts from current dev. Conflicts escalate to team-lead (no silent --abort, no --no-verify, no --hard reset).

### Fixed — preflight threshold doc drift

SKILL.md previously said "disk ≥ 30 GB / compressor < 4 GB"; preflight.sh implements "disk ≥ 20 GB / compressor < 6 GB / swap < 1 GB" (per user spec). Doc updated to match implementation.

### Fixed — CLAUDE_PLUGIN_ROOT silent broken

`${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}` fallback was a developer-only path. End-users install the plugin under `~/.claude/plugins/cache/{marketplace}/{plugin}/{version}/` and the fallback would silently resolve to a non-existent path, producing `script not found` errors with no clear cause.

Replaced everywhere with `${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set in this Agent Teams session}` so a missing env var fails immediately with a clear message instead of silently breaking.

### Verified end-to-end (17-step test suite, all pass before commit)

```
Test 1   cold rebuild                          OK (96585-byte raw + executable wrapper)
Test 2   cache hit                             21 ms
Test 3   wrapper file content                  nix bash 5 shebang verified
Test 4   bash 3.2 caller → nix tools           ✅ pnpm / git / node / gh / biome / maestro
Test 5   zsh caller → nix tools                ✅
Test 6   fish caller → nix tools               ✅
Test 7   shellHook env vars exported           PNPM_HOME / PLAYWRIGHT_BROWSERS_PATH / MAESTRO_DRIVER_STARTUP_TIMEOUT
Test 8   pnpm/node/git/gh real exec            10.29.2 / 22.20.0 / 2.50.1 / 2.72.0
Test 9   touch flake.nix only → cache hit      ✅ (content unchanged)
Test 10  real content edit → rebuild           ✅
Test 11  content restored → rebuild            ✅
Test 12  cache hit after restore               ✅
Test 13  lane-3 separate worktree              separate env, hash-distinct
Test 14  unset CLAUDE_PLUGIN_ROOT              hard fail with clear message
Test 15  git via wrapper                       ✅ rev-parse / remote / status
Test 16  compound shell command via wrapper    ✅
Test 17  monitoring start preparation          confirmed manual start.sh
```

### Migration

3.3.0 users: nothing to do; `/harness-team-lead` Step 0.5 invokes the new `build-dev-env.sh` and your worktrees get the wrapper auto-built. Old `.harness-devenv.sh` files are obsolete (the new artifacts are `.harness-devenv-raw.sh` + executable `devshell`); they're harmless to leave in place but can be removed.

Engineers who scripted `source $DEV_ENV` from a custom override must switch to `"$DEVSH" <command>` form.

## [3.3.0] — 2026-05-10

### Fixed — Per-worktree dev shell with content-hash cache invalidation

3.2.0 shipped one shared env file at `<project-root>/.my-harness/.harness-devenv.sh` that all 4 lanes sourced. Two correctness gaps surfaced under realistic use:

1. **Per-lane `flake.nix` edits were silently ignored.** Lane-3 may be working on an issue that itself modifies `flake.nix` (e.g. `flake-nix-direnv` setup, adding a tool to the dev shell). With one shared file, lane-3 sourced lane-1's evaluation of the project master flake — its own edits never took effect inside its own work.
2. **mtime-based cache invalidation was unsound on macOS bash.** macOS bash's `[ A -nt B ]` operator compares whole-second mtimes only. A `vim flake.nix; :wq` followed immediately by re-running the build script in the same wall-clock second would silently reuse the stale cache. Real reproduction in tests showed `touch flake.nix && rerun` returning a cache hit when it should have rebuilt.

Fix:

- `skills/harness-team-lead/scripts/build-dev-env.sh` rewritten to be **per-worktree + content-hash-cached**. The script now:
  - Walks up from the supplied path to the nearest `flake.nix` (worktree first, then project master).
  - Writes the env file at `<flake-dir>/.my-harness/.harness-devenv.sh` — per worktree, not project-shared.
  - Caches by `sha256(flake.nix + flake.lock)` written as a marker line at the top of the env file. Cache check reads the first line and compares against the current hash. Cache hit ≈ 7 ms.
  - Hash-based invalidation: real content edits **always** trigger rebuild even within the same wall-clock second; pure `touch` (mtime-only change) does **not** force a needless rebuild.
- All 4 agent definitions updated to the per-worktree pattern. Each teammate now runs:
  ```bash
  DEV_ENV=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/harness-team-lead/scripts/build-dev-env.sh" "$WORKTREE")
  source "$DEV_ENV"
  ```
  at the start of every turn, where `$WORKTREE` is supplied by analyst-N's ASSIGNMENT / REVIEW / TEST message.
- `skills/harness-team-lead/SKILL.md` Step 0.5 reframed as a **warmup** for the project root flake. /nix/store is system-shared, so warming pre-populates derivations; per-lane builds afterwards are evaluator-cache hits and finish in seconds.
- `skills/harness-nix-pure/SKILL.md` updated to document the per-worktree pattern as the canonical in-team default; the old "one shared env file" wording was removed.

### Verified

```
Test 1 cold build       — OK    (96860 bytes, ~6 s nix print-dev-env)
Test 2 cache hit (no edit)            — 7 ms instant (correct)
Test 3 touch flake.nix only           — cache hit (correct: no content change)
Test 4 real content edit (echo)       — rebuild fired (correct)
Test 5 restore content (sed)          — rebuild fired (correct)
Test 6 lane-3 separate worktree       — separate env file, hash-distinct
After source: pnpm/git/gh/node all resolve from /nix/store
```

### Migration

Existing 3.2.0 users: the project-shared env file at `<root>/.my-harness/.harness-devenv.sh` is no longer authoritative. It will be regenerated on first `/harness-team-lead` Step 0.5 with the new hash-marker format. Lane teammates each maintain their own env at `<lane-worktree>/.my-harness/.harness-devenv.sh` — no cleanup needed; old files are simply rebuilt with new markers on next use.

## [3.2.0] — 2026-05-10

### Added — Pre-built dev shell environment (eliminates `nix develop --command` fork-bomb at the source)

3.1.0's `lane-lock.sh` was a band-aid. The real waste was every engineer / analyst / e2e-reviewer / reviewer running `nix develop --command <cmd>` per command — each call re-evaluates the flake, runs shellHook, forks helper processes (verified at ~200 helpers per call). With 4 lanes × ~10 commands/lane × evaluator fork = ~1000 node helpers in 90 seconds = compressor saturation = kernel-watchdog panic.

Fix: evaluate the flake **once per `/harness-team-lead` session** (`nix print-dev-env --impure` → bash dump) and have all 4 lanes `source` the resulting file. After source, the dev shell's PATH / env vars / shell functions are active in the engineer's bash. Running `pnpm install` / `vitest` / `biome` / `tsc` / `git` / `gh` is direct — zero nix evaluator fork.

- New `skills/harness-team-lead/scripts/build-dev-env.sh` — runs `nix print-dev-env --impure <flake>`, validates non-empty bash output, atomically writes to `<project-root>/.my-harness/.harness-devenv.sh`. Appends a final line that restores `$nix_saved_PATH` so system tools (git, gh, coreutils) remain available alongside the nix-provided ones (pnpm, node, bun, …). Verified on the user's flake: file is ~96 KB, all of pnpm 10.15.1 / node 22.20.0 / git 2.50.1 / gh 2.72.0 resolve from /nix/store after source.
- `skills/harness-team-lead/SKILL.md` — new "Step 0.5 — Pre-build the shared dev shell environment". Mandatory between Codex daemon start (Step 0) and issue source detection (Step 1). Idempotent: subsequent `/harness-team-lead` invocations regenerate.
- `agents/harness-engineer.md` — "Mandatory" section rewritten. Engineers source `$PROJECT_ROOT/.my-harness/.harness-devenv.sh` once at start of turn, then run pnpm / vitest / biome / tsc / git directly. `nix develop --command` is hard-prohibited. The "Optional lane-lock" became "Mandatory: lane-lock the first `pnpm install` per worktree" — pnpm's own worker pool is still ~50–100 helpers per call, so the first install per fresh worktree is still serialized; subsequent installs are cache-resolved and skip the lock.
- `agents/harness-analyst.md` Step 5 — analyst sources the env before `git add / commit / push / gh pr create`. The dev shell provides git + gh from /nix/store, so the husky pre-commit hook (which runs biome / tsc / vitest / gitleaks) succeeds. Without this, husky's pnpm lookup would fail.
- `agents/harness-e2e-reviewer.md` — sources the env, runs playwright / maestro directly. First install gets `lane-lock pnpm-install`.
- `agents/harness-reviewer.md` — sources the env for the detection block (biome / tsc / grep). No more `nix develop --command sh -c '...'`.
- `skills/harness-nix-pure/SKILL.md` — canonical rule reference. Documents source-based pattern as the in-team default; `nix develop --command` is reserved for one-shot user invocations outside the team.

### Why this beats direnv

direnv requires `direnv allow` per worktree — manual user step, per-worktree cache, 4 lanes each pay first-allow cost. The pre-built file is one shared artifact regenerated once per session; all 4 lanes immediately reuse it with no setup ceremony.

### Migration

Existing 3.1.0 users: nothing to do; `/harness-team-lead` runs `build-dev-env.sh` automatically at Step 0.5. The env file lands at `<root>/.my-harness/.harness-devenv.sh` and is gitignored via the existing `.my-harness/` ignore pattern.

If your engineer / analyst / reviewer was instructed to use `nix develop --command` from a custom override, that path now contradicts the rule. Switch to the source pattern and remove the wrapper.

## [3.1.0] — 2026-05-10

### Added — `lane-lock.sh` to prevent fork-bomb panic from concurrent `nix develop --command pnpm install`

Real-world incident timeline (16 GB MacBook Air, observed via `~/harness-monitor/snapshot.log`):

- 04:38 baseline: 7 node processes
- 04:39:33 (after analyst-2 dispatched engineer-2): 41 node
- 04:39:38: 66 node (+25 in 5 s)
- 04:39:54 (engineer-2 ran `nix develop --command pnpm install`): swap kicked in, compressor 1098 MB → 7211 MB in one snapshot
- 04:40:20: 401 node
- 04:41:33: 1006 node
- 04:43:37: 1026 node, free 22 MB, compressor 5267 MB, swap 44.4 GB / 45 GB used
- 04:48:26: kernel panic — `Compressor Info: 100% of segments limit (BAD)`, 44 swapfiles

Root cause: `nix develop --command pnpm install` (and `pnpm exec vitest` / `pnpm exec tsc` / `pnpm exec biome`) each fork 200+ helper node processes per call. With 4 engineer lanes running concurrently, ~1000 node processes appear within 90 s, saturating the macOS memory compressor and triggering the kernel watchdog. The harness's previous `agents/harness-engineer.md` wording (load `harness-nix-pure` and run `nix develop --command pnpm install`) combined with `harness-team-lead`'s 4-lane parallel design made this collision the default outcome — a true contradiction between two skill rules.

Fix:

- New `skills/harness-team-lead/scripts/lane-lock.sh <lock-name> <command...>`. Uses `mkdir`-atomic locks (POSIX, macOS-compatible — `flock(1)` is Linux-only and silently no-ops on macOS). Lock dir lives at `<project-root>/.my-harness/.<lock-name>.lockdir`, project-scoped, survives across worktrees, self-cleans on EXIT / SIGINT / SIGTERM, reclaims stale locks via dead-pid check.
- `agents/harness-engineer.md` gains a hard "Mandatory: serialize heavy nix-develop commands via lane-lock" section. Every `nix develop --command pnpm install` / `pnpm exec vitest` / `pnpm exec tsc` / `pnpm exec biome` MUST be wrapped: `bash $LL <lock-name> nix develop --command ...`.
- `skills/harness-nix-pure/SKILL.md` documents the same rule as the canonical reference.

After lock acquisition, the first lane warms the nix store and the pnpm store; subsequent lanes resolve from cache (~10x faster, ~10x fewer helpers). The serialized phase is bounded to install / typecheck / test / biome boundaries — actual implementation work in editor / file ops still proceeds in parallel across lanes.

### Migration

If you ran 2.x or 3.0.0 successfully on a beefy machine (≥ 32 GB RAM): nothing to do. The lock is best-effort serialization and does not change command semantics, only timing.

If your machine OOM-ed with 3.0.0: confirm `agents/harness-engineer.md` has the new "Mandatory" section and that `bash skills/harness-team-lead/scripts/lane-lock.sh` is on disk. The next `/harness-team-lead` run will use the lock automatically (engineers read the new rule from their system prompt).

## [3.0.0] — 2026-05-10

### Added — kernel-panic prevention for /harness-team-lead (BREAKING)

Earlier real-world runs of `/harness-team-lead` on a 16 GB MacBook Air produced two distinct catastrophes:

1. macOS kernel watchdog panic (91-second freeze, full reboot) when `nix-collect-garbage` was launched from inside the skill on a near-full disk while 16 in-process teammates were active. Compressor reached 96% of segments, swap exhausted at 36 GB, 859 node processes alive at the moment of panic.
2. ENOSPC stalls on engineer lanes when `pnpm install` / `vitest` were invoked under disk pressure.

Root causes (now structurally prevented):

- **No resource gate**. The skill happily entered with `< 10 GB` disk and `compressor > 4 GB`.
- **Non-idempotent `/loop` re-entry**. Each `/loop` wakeup re-evaluated state, re-spawned `nix-collect-garbage`, re-issued `TeamCreate` against an existing team. Multiple GCs raced for disk; team-create error responses tempted the LLM to delete-and-recreate (= 16 fresh teammates on top of 16 alive ones).
- **In-skill background jobs**. `nohup nix-collect-garbage -d &` from inside the skill outlived the lead session and pile-piled across wakeups.

Fixes (all extracted to `skills/harness-team-lead/scripts/` shell files — SKILL.md no longer carries inline operational bash):

- `scripts/preflight.sh` — hard gate. Refuses to start if any of:
  - Data volume `< 20 GB` available
  - reclaimable RAM (free + inactive + speculative) `< 1 GB`
  - `vm.compressor_bytes_used > 6 GB`
  - swap used `> 1 GB`
  - any `nix-collect-garbage` / `nix-store --gc` already running
  - `.my-harness/.config` missing
  Surfaces the remediation steps to stderr and exits non-zero. Caller must propagate.
- `scripts/check-agent-teams-enabled.sh` — idempotent settings.json + env check.
- `scripts/check-team-exists.sh` — emits one of `skip` / `create` / `broken`. `skip` means the existing team is fully populated and Step 2 must NOT call `TeamCreate` or any of the 16 `Agent({})` calls. This is the structural fix for `/loop` re-entry duplicate spawn.
- `scripts/list-pending-issues.sh` — replaces inline `gh issue list` / `find docs/task/child` branching. One canonical script, auto-detects `USE_GITHUB_ISSUES` from `.my-harness/.config`.

Hard prohibitions added to SKILL.md:

- Skill MUST NEVER invoke `nix-collect-garbage` / `nix-store --gc`. Lane blocks caused by ENOSPC are reported to the user (one `[lane=N status=blocked-disk-full]` message); the user runs cleanup externally before saying `resume lane N`.
- Skill MUST NEVER spawn long-running background jobs (`nohup ... &`).
- Skill MUST NEVER call `TeamCreate` while `~/.claude/teams/harness-team/config.json` exists. Disk-recover via `TeamDelete` is a separate, manual decision.

### Changed (BREAKING) — `scripts/codex-daemon.sh` moved into the owning skill

- `scripts/codex-daemon.sh` → `skills/harness-codex-daemon/scripts/codex-daemon.sh`. The skill now owns its single implementation script. SKILL.md invokes the new path directly; the previous wrapper layer (`start.sh` / `stop.sh` etc.) was removed as dead indirection.
- Any external automation that hard-coded `scripts/codex-daemon.sh` must update its path. Internal references (README, CHANGELOG, `scripts/codex-app-server-call.py`) have been updated.

### Changed — agent definitions slimmed

- `agents/harness-{analyst,engineer,e2e-reviewer,reviewer}.md` frontmatter `tools:` field no longer lists `SendMessage`. SendMessage is a deferred tool — listing it had no effect (each teammate still ran `ToolSearch select:SendMessage` before first use). The bogus declaration is removed.
- `agents/harness-engineer.md` body — the `## Code discipline`, `## Nix pure`, and `## TDD` sections were removing duplicated rule content already owned by the dedicated rule skills (`harness-tdd`, `harness-jsdoc`, `harness-hono-clean-arch`, `harness-drizzle-rules`, `harness-design-rules`, `harness-nix-pure`, `harness-no-hardcoded-secrets`). Replaced with a single `## Conventions` section that references the skills by name. Engineer system prompt is ~30 lines shorter; rules live in exactly one place.

### Changed — `harness-team-lead` Step 2 spawn prompt is no longer redundant

- Per-teammate spawn prompt no longer embeds runtime values (`USE_CODEX=...`, `USE_CODEX_ENGINEER=...`, etc.). Each teammate reads `.my-harness/.config` itself when needed. Prompt template went from ~900 chars to ~150 chars.

### Migration

Existing projects on 2.x using `/harness-team-lead`:

1. The skill will refuse to start if disk is `< 20 GB` or RAM/compressor is in real pressure. Run a cleanup externally (e.g. `bash ~/harness-monitor/cleanup.sh` if you adopted the optional auto-cleanup helper) and retry.
2. If you scripted against `scripts/codex-daemon.sh`, update the path to `skills/harness-codex-daemon/scripts/codex-daemon.sh`.
3. Existing `harness-team` from a prior run will be reused — Step 2 emits `skip`. To force a fresh team, manually `rm -rf ~/.claude/teams/harness-team/` and rerun (the lead will then run TeamCreate + 16 `Agent({})`).

## [Unreleased]

### Fixed — `dev/dev/talk` path collision in conversation log hooks

- `hooks/log-user-prompt.sh` and `hooks/log-claude-output.sh` walked up from `cwd` to find `.my-harness/.config`, then hardcoded `$PROJECT_ROOT/dev/docs/talk` as the log target. Because `bootstrap.sh` writes `.my-harness/.config` BOTH at the project root and inside each worktree, running `claude` from the `dev/` worktree produced `<root>/dev/dev/docs/talk/...` paths. The hooks now detect when `PROJECT_ROOT`'s parent already has `.my-harness/.config` (= we are inside a worktree) and skip the `dev/` prefix in that case. Both starting points (`<root>` and `<root>/dev`) now resolve to the same canonical `<root>/dev/docs/talk/<date>.md`.

### Changed — bypass-permissions by default for Codex calls and Claude Code

- `~/.claude/settings.json` is set to `"defaultMode": "bypassPermissions"` (was `"auto"`). Claude Code is the outer review boundary in Agent Teams runs; the per-tool prompt would just block 16 lanes on every shell.
- `scripts/codex-app-server-call.py` now sets `approval_policy="never"` and `sandbox="danger-full-access"` on every `ThreadConfig`. Override with the new `--no-bypass` flag for paranoid runs.

### Hardened — bootstrap.sh, daemon, install-rtk

- `scripts/bootstrap.sh` `ensure_worktree`: previously WARNED + skipped when a non-worktree directory was already present at `main/` `stage/` or `dev/`, so a half-completed first run could silently leave the user with only `dev/`. Now ERRORS and tells the user to `rm` it. A final post-loop check verifies all three worktrees have `.git` markers; if any is missing, the script exits 1 with `git worktree list` output for diagnosis.
- `skills/harness-codex-daemon/scripts/codex-daemon.sh` `cmd_start`: runs `check-codex-auth.sh` and prints a `::warning::` if codex is not logged in (the daemon itself starts fine but every turn would fail). Truncates `~/.codex/my-harness-daemon.log` on each start so it never grows unbounded across long-lived sessions.
- `scripts/install-rtk.sh` `write_config`: skip condition broadened from "exclude_commands key present" to "either `[hooks]` section OR `exclude_commands` key present" — prevents a TOML duplicate-section error if a future RTK auto-patch starts writing a bare `[hooks]` header.

### Added — Codex memory optimization (2.2.0 candidate)

- **Top-level `flake.nix`** at the repo root provides the entire harness runtime via `nix develop` / `direnv allow`: `codex` CLI, `rtk`, Python 3.13 with `codex-app-server-sdk` + `websockets` + `pydantic`, plus jq / curl / coreutils. A fresh Mac, Linux box, or WSL2 environment with only Nix installed is now sufficient — no `brew install`, no `npm -g`, no `pip --user`. See README → "Fresh machine setup".
- **`nix/codex-app-server-sdk.nix`** — custom `buildPythonPackage` derivation for the SDK (not yet in nixpkgs). hatchling backend, depends on `pydantic` + `websockets`, AGPL-3.0.
- **`scripts/codex-app-server-call.py`** — Python SDK client that replaces the legacy per-call `codex exec` invocation. Connects via WebSocket to a shared daemon when available, otherwise spawns its own stdio app-server. Drains streamed events, emits only the final `agent_message` text on stdout.
- **`skills/harness-codex-daemon/scripts/codex-daemon.sh`** + **`skills/harness-codex-daemon/`** — lifecycle manager for the shared daemon (`start` / `stop` / `status` / `restart` / `logs` / `doctor`), exposed as a skill so callers do not need to inline bash. Listens on `ws://127.0.0.1:7373`. Measured 55% peak-RAM reduction across 3 concurrent lanes (271 MB → 120 MB) on macOS arm64; ~85% projected at 16 lanes.
- **`skills/harness-team-lead/SKILL.md`** — Step 0 invokes `harness-codex-daemon` with action `start` before issue dispatching, Step 4 invokes it with `stop` on shutdown.
- **`scripts/install-codex-sdk.sh`** — venv-based fallback for users without Nix. Creates `$HOME/.codex/my-harness-venv` and `pip install`s the SDK. Auto-skipped when the flake's shellHook has set `MY_HARNESS_CODEX_PY`.
- **`scripts/install-rtk.sh`** — one-shot installer for [RTK](https://github.com/rtk-ai/rtk), the PreToolUse hook that compresses Bash output (git / find / grep / etc.) by 60-90% before it reaches Claude's context. Backs up `~/.claude/settings.json`, runs `rtk init -g --auto-patch`, writes `~/.config/rtk/config.toml` with `codex` / `codex-ask.sh` / `claude` excluded so wrapper output is never rewritten.
- **Per-call plugin disable** in `codex-ask.sh` and the Python helper. Set `$MY_HARNESS_CODEX_DISABLE_PLUGINS="cloudflare@openai-curated,sentry@openai-curated,..."` (or pass `--disable-plugin` repeatedly) and `[plugins."<id>"] enabled = false` overrides are passed via `-c` for that single invocation only — your `~/.codex/config.toml` stays untouched.
- **`.envrc`** — `use flake`, so `direnv allow` once gives you the dev shell on every `cd`.

### Changed — codex-ask.sh internals

- Replaced the legacy `codex exec` / `codex exec resume` cold-start invocation with a JSON-RPC 2.0 conversation over the official Python SDK. Public CLI surface (`--role`, `--context`, `--session`, `--out`, `--log`, `--reset-session`, `--set-active`) is unchanged. Existing `$SESSION_DIR/$KEY.id` files migrate transparently — Codex 0.128 thread IDs are byte-compatible with the SDK's `thread/resume`.
- The auth pre-flight, rescue-state generation, role-prefix injection, and context-file attachment all still run unchanged; only the underlying Codex transport changed.

### Changed (BREAKING) — Agent Teams architecture

- `/harness-team-lead` is now an **Agent Teams** orchestrator (requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `~/.claude/settings.json`). It calls `TeamCreate("harness-team")` once and instantiates **16 persistent teammates** (4 lanes × 4 roles): `analyst-1..4`, `engineer-1..4`, `e2e-reviewer-1..4`, `reviewer-1..4`. Teammates stay alive for the whole session.
- Per-lane orchestration: team-lead only sends issue assignments to `analyst-N` (the lane foreman). analyst-N dispatches `engineer-N` → `e2e-reviewer-N` → `reviewer-N` via `SendMessage`, loops on failures, then runs `git commit` + `git push` + `gh pr create` itself (analyst-N is the only teammate that touches git in its lane).
- After each issue's PR completes, team-lead sends `DIRECTIVE: clear_context` to **all 4 teammates of that lane**; each invokes `/clear` in its own session before the next assignment (fresh-agent-per-issue).
- Removed the dead `agents/harness-team-lead.md` subagent definition. team-lead is the slash command (`skills/harness-team-lead/SKILL.md`); it never gets spawned as a subagent. The previous design relied on nested subagent spawning, which is forbidden by Claude Code (and by Agent Teams' "No nested teams" limitation).
- Reworked `agents/harness-analyst.md`, `harness-engineer.md`, `harness-e2e-reviewer.md`, `harness-reviewer.md` to be teammate definitions (tools = `SendMessage` instead of `Agent`/`Task`). Each agent type is instantiated 4× by team-lead.

### Changed (BREAKING) — Cloudflare IaC: OpenTofu → Alchemy v2

- Cloudflare infrastructure-as-code is now **Alchemy v2** (`alchemy@2.0.0-beta.x`, Effect.ts based). Replaces the previous OpenTofu / Terraform path entirely.
- `templates/nix/flake.nix` now provides `bun` (Alchemy v2's recommended runtime) instead of `opentofu`. `wrangler` is kept for D1 migration commands.
- `skills/harness-deploy-setup/SKILL.md` rewritten end-to-end: `bun add alchemy effect @effect/platform-bun @effect/platform-node` → generate `dev/alchemy.run.ts` (Effect.gen + `yield*`) → `bunx alchemy login --configure` → `bunx alchemy plan/deploy --stage <env>`. State store lives on Cloudflare (Worker + Durable Object); no AWS dependency.
- `docs/INFRA.md` "Using Cloudflare (Terraform-managed)" section replaced by "Cloudflare IaC — Alchemy v2" with a resource coverage table, a sample `dev/alchemy.run.ts`, and SOPS-decrypted env-var injection pattern.
- `docs/SETUP.md` now lists `CLOUDFLARE_ACCOUNT_ID` alongside `CLOUDFLARE_API_TOKEN`. R2 bucket creation example switched to `bunx alchemy deploy --stage prod`.
- `skills/harness-nix-pure/SKILL.md` example commands updated (`terraform apply` → `bunx alchemy deploy --stage dev`).
- `skills/harness-deploy-execute/SKILL.md` Prerequisites updated to reference `bunx alchemy deploy` instead of `terraform apply`.
- `README.md` / `README.ja.md` lifecycle table cell updated: "Terraform infra" → "Alchemy v2 (Effect.ts) infra script".
- **Cloudflare Pages remains intentionally out of scope** (not implemented in Alchemy v2 anyway). Static sites should use `Cloudflare.Worker` + Workers Static Assets.

### Migration notes

- Existing projects on the old subagent-spawning architecture must enable Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) and re-run `/harness-team-lead` to instantiate the new 16-teammate team. Old subagent context is discarded.
- Existing projects with OpenTofu-managed Cloudflare resources can adopt them into Alchemy v2 via `bunx alchemy deploy --stage <env> --adopt` (per-resource adoption is also supported by adding `adopt: true` in `dev/alchemy.run.ts`).
- Pin `alchemy` to a specific `2.0.0-beta.x` in `package.json`; the v2 series may introduce breaking changes during beta.

### Added

- `/my-harness-init` Phase 1 now asks how you want to authenticate Codex (ChatGPT subscription via `codex login`, or API key via `OPENAI_API_KEY`) immediately after `USE_CODEX=yes` is confirmed. The choice is persisted as `CODEX_AUTH=subscription|api-key` in `.my-harness/.config` and `init-state.json`. Auth-failure guidance (LANG=en + LANG=ja) branches on the chosen method: subscription failures instruct the user to run `codex login`; API key failures show exact `export` / `set -x` commands for bash/zsh/fish plus the persistent `~/.zshrc` path. After 3 consecutive failures the skill auto-sets `USE_CODEX=no` and offers to switch methods.
- `bootstrap.sh` interactive mode asks `Codex auth method (subscription/api-key)` when `USE_CODEX=yes` and writes `CODEX_AUTH=...` to `.my-harness/.config`. Non-interactive mode defaults to `CODEX_AUTH=subscription` when not supplied. When `USE_CODEX=no`, `CODEX_AUTH` is written as empty.
- `codex-ask.sh` now reads `CODEX_AUTH` from `.my-harness/.config` at startup and branches the rescue `next_action` field: `subscription` → "Run `codex login` then say `resume`"; `api-key` → "Re-export OPENAI_API_KEY (verify on https://platform.openai.com) then say `resume`". The stderr rescue hint follows the same branch.

- `bootstrap.sh` now writes `<root>/start-dev.sh` — a portable launcher (`cd "$HERE/dev" && exec claude "$@"`) that starts a Claude Code session rooted at `<root>/dev/` in one command. The script ends with `exec claude` so signals (Ctrl+C) propagate cleanly to Claude.
- `/my-harness-init` Phase 8.6 closing message now explicitly explains that Claude Code has no documented mid-session CWD-change mechanism. The message (bilingual: en + ja) directs the user to exit the current session and run `start-dev.sh` (or `cd <root>/dev && claude`) before running `/harness-team-lead`.
- Bootstrap "next steps" banner replaced with one that highlights the session-restart requirement first, includes `vitest run` health-check, and shows `start-dev.sh` as the recommended entry point.
- README.md and README.ja.md Quick Start sections updated to note the session-restart requirement and the `start-dev.sh` launcher.
- Project lifecycle tables in both READMEs gained row **3.5. Switch session** between Tasks (phase 3) and Implementation (phase 4).

### Removed

- Removed `CODEX_AUTH=api-key` path entirely. Codex CLI uses ChatGPT subscription auth via `codex login`; the API-key UI, `OPENAI_API_KEY` auto-load, and subscription-vs-api-key branching in `codex-ask.sh` / `bootstrap.sh` / `SKILL.md` were misguided. Users now only need to install Codex CLI (`npm install -g @openai/codex`) and run `codex login`.

### Fixed

- Restored `USE_GLOBAL_CLAUDE` option with a real `claudeMdExcludes` implementation. Earlier commit `687481f` had deleted it under the mistaken belief that Claude Code couldn't honor it. The setting is now genuinely respected — when set to `no`, `dev/.claude/settings.json` is written with the absolute path of `~/.claude/CLAUDE.md` in `claudeMdExcludes`, and Claude Code skips that file at session start. Claude Code's official `claudeMdExcludes` field in `settings.json` is what makes this work; `${HOME}` is expanded to the absolute path so Claude Code can match it against the file system.

## [1.0.0] - 2026-05-04

### Added (Plugin first release)

- Packaged as a Claude Code plugin (`marketplace.json` + `plugin.json`)
- 20 skills:
  - Top-level 2: `my-harness-generator`, `my-harness-init`
  - Convention 10: `harness-tdd`, `harness-hono-clean-arch`, `harness-drizzle-rules`, `harness-nix-pure`,
    `harness-design-rules`, `harness-jsdoc`, `harness-git-discipline`, `harness-no-hardcoded-secrets`,
    `harness-mask`, `harness-codex-consult`
  - Shell wrappers 8: `harness-new-feature`, `harness-new-hotfix`, `harness-resolve-conflict`,
    `harness-sync-features`, `harness-check-codex-auth`, `harness-check-secrets`,
    `harness-setup-secrets`, `harness-branch-protection`
- 4 worker agent definitions: `harness-analyst`, `harness-engineer`, `harness-e2e-reviewer`,
  `harness-reviewer`. Each is instantiated 4× by `/harness-team-lead` to form a 16-teammate
  Agent Teams team (4 lanes × 4 roles): analyst-1..4, engineer-1..4, e2e-reviewer-1..4, reviewer-1..4.
  All 16 teammates are persistent — created once at session start, kept alive for the whole session.
- Per-lane orchestration: analyst-N is the lane foreman. team-lead only sends issue assignments to
  analyst-N (never directly to engineer/e2e/reviewer). analyst-N dispatches engineer-N → e2e-reviewer-N
  → reviewer-N via `SendMessage`, loops on failures, then runs `git commit` + `git push` +
  `gh pr create` itself (analyst-N is the only teammate that touches git in its lane).
- After each issue's PR is created, team-lead sends `/clear` to all 4 teammates of that lane
  (analyst-N, engineer-N, e2e-reviewer-N, reviewer-N) to enforce fresh-agent-per-issue, then
  dispatches the next pending issue to that lane.
- `/harness-team-lead` is owned by `skills/harness-team-lead/SKILL.md` (the team lead skill);
  `TeamCreate` once at start, `TeamDelete` at session end.
- **Requires** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `~/.claude/settings.json` because the
  architecture relies on persistent teammates and `SendMessage`-based coordination, both of which
  exist only inside Agent Teams.
- 2 hooks (`hooks.json`):
  - `UserPromptSubmit`: Automatically masks user input with mask-secrets.sh and appends to dev/docs/talk/<date>.md
  - `Stop`: Extracts Claude's final response from transcript, masks it, and appends
- 22 shell scripts (bootstrap / codex-ask / mask-secrets / various setup / hooks, etc.)
- Secret masking (9 patterns: API keys / AWS / email / phone / card / JWT / PEM / URL credentials / KEY=value format)
- bootstrap `--config <file>` non-interactive mode (for calling from `/my-harness-init`)
- True multi-turn dialogue via Codex CLI session resume
- USE_GITHUB_ISSUES=no support (`docs/task/auto/<id>.md` fallback)
- `dev/.claude/CLAUDE.md` always generated with project conventions (global `~/.claude/CLAUDE.md` still loads per Claude Code design; local conventions augment it)
- iOS / Android templates, Cloudflare D1 + Drizzle, Resend, Playwright + Maestro

### Architecture
- Skills-centric: detailed rules split into individual skills, lazy-loaded by Claude as needed
- Shell scripts are called via skills (Claude doesn't need to remember arguments)
- Hooks mechanically record conversations (insurance against Claude forgetting to log)
- pre-commit runs gitleaks + check-forbidden-patterns as double defense
