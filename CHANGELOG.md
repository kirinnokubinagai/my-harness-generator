# Changelog

All notable changes to this plugin documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Fixed — `dev/dev/talk` path collision in conversation log hooks

- `hooks/log-user-prompt.sh` and `hooks/log-claude-output.sh` walked up from `cwd` to find `.my-harness/.config`, then hardcoded `$PROJECT_ROOT/dev/docs/talk` as the log target. Because `bootstrap.sh` writes `.my-harness/.config` BOTH at the project root and inside each worktree, running `claude` from the `dev/` worktree produced `<root>/dev/dev/docs/talk/...` paths. The hooks now detect when `PROJECT_ROOT`'s parent already has `.my-harness/.config` (= we are inside a worktree) and skip the `dev/` prefix in that case. Both starting points (`<root>` and `<root>/dev`) now resolve to the same canonical `<root>/dev/docs/talk/<date>.md`.

### Changed — bypass-permissions by default for Codex calls and Claude Code

- `~/.claude/settings.json` is set to `"defaultMode": "bypassPermissions"` (was `"auto"`). Claude Code is the outer review boundary in Agent Teams runs; the per-tool prompt would just block 16 lanes on every shell.
- `scripts/codex-app-server-call.py` now sets `approval_policy="never"` and `sandbox="danger-full-access"` on every `ThreadConfig`. Override with the new `--no-bypass` flag for paranoid runs.

### Hardened — bootstrap.sh, daemon, install-rtk

- `scripts/bootstrap.sh` `ensure_worktree`: previously WARNED + skipped when a non-worktree directory was already present at `main/` `stage/` or `dev/`, so a half-completed first run could silently leave the user with only `dev/`. Now ERRORS and tells the user to `rm` it. A final post-loop check verifies all three worktrees have `.git` markers; if any is missing, the script exits 1 with `git worktree list` output for diagnosis.
- `scripts/codex-daemon.sh` `cmd_start`: runs `check-codex-auth.sh` and prints a `::warning::` if codex is not logged in (the daemon itself starts fine but every turn would fail). Truncates `~/.codex/my-harness-daemon.log` on each start so it never grows unbounded across long-lived sessions.
- `scripts/install-rtk.sh` `write_config`: skip condition broadened from "exclude_commands key present" to "either `[hooks]` section OR `exclude_commands` key present" — prevents a TOML duplicate-section error if a future RTK auto-patch starts writing a bare `[hooks]` header.

### Added — Codex memory optimization (2.2.0 candidate)

- **Top-level `flake.nix`** at the repo root provides the entire harness runtime via `nix develop` / `direnv allow`: `codex` CLI, `rtk`, Python 3.13 with `codex-app-server-sdk` + `websockets` + `pydantic`, plus jq / curl / coreutils. A fresh Mac, Linux box, or WSL2 environment with only Nix installed is now sufficient — no `brew install`, no `npm -g`, no `pip --user`. See README → "Fresh machine setup".
- **`nix/codex-app-server-sdk.nix`** — custom `buildPythonPackage` derivation for the SDK (not yet in nixpkgs). hatchling backend, depends on `pydantic` + `websockets`, AGPL-3.0.
- **`scripts/codex-app-server-call.py`** — Python SDK client that replaces the legacy per-call `codex exec` invocation. Connects via WebSocket to a shared daemon when available, otherwise spawns its own stdio app-server. Drains streamed events, emits only the final `agent_message` text on stdout.
- **`scripts/codex-daemon.sh`** + **`skills/harness-codex-daemon/`** — lifecycle manager for the shared daemon (`start` / `stop` / `status` / `restart` / `logs` / `doctor`), exposed as a skill so callers do not need to inline bash. Listens on `ws://127.0.0.1:7373`. Measured 55% peak-RAM reduction across 3 concurrent lanes (271 MB → 120 MB) on macOS arm64; ~85% projected at 16 lanes.
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
