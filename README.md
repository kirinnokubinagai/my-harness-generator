# my-harness-generator

> A Claude Code plugin that turns "I have a vague idea" into a fully scaffolded, production-ready project — in one conversation.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-orange.svg)](https://code.claude.com)
[![日本語](https://img.shields.io/badge/lang-日本語-red.svg)](./README.ja.md)

[日本語版はこちら / Japanese version](./README.ja.md)

## What it does

Runs a structured interview, optionally consults Codex for second opinions, generates logo + UI mocks, settles the stack, and produces a fully wired-up **production-grade** monorepo with branch protection, CI, git hooks, security middleware, runbooks, and parallel-lane conventions — from one slash command. First commit is green, `main`/`stage`/`dev` are protected, every conversation auto-logs to `dev/docs/talk/` with secrets masked.

## Production-grade by default (5.0+)

The harness no longer scaffolds an MVP that you have to harden later. Everything that's hard to retrofit is wired in at bootstrap:

- **Hono middleware suite** — security headers (CSP/HSTS/COOP/CORP/Permissions-Policy), KV-backed rate limiting, structured logging (pino + `x-request-id`), idempotency (`Idempotency-Key`), strict CORS allowlist
- **Health endpoints** — `/healthz` / `/readyz` (DB ping + smoke checks) / `/livez`
- **Observability + supply chain** — Sentry init, audit-log helper, feature-flag helper (with stable-hash % rollout), CodeQL, CycloneDX SBOM, license audit, k6 smoke, Lighthouse CI, Renovate, Dependabot
- **Six runbook templates** — `incident-response.md` / `deploy.md` / `rollback.md` / `dr-plan.md` / `oncall.md` / `postmortem.md` (blameless 5-whys)
- **Pre-launch checklist** in `rules/production.md` — backup-restore drill, ZAP full scan, load test, CSP enforcement, chaos drill, on-call rotation
- **OS-aware `MAX_LANES` recommendation** that accounts for macOS memory compression + live `memory_pressure` (a 16 GB Mac in green pressure correctly recommends 4 lanes — the runtime gate is the safety net)

See [`docs/PRODUCTION.md`](./docs/PRODUCTION.md) for the file-by-file map.

## Highlights

- **`/my-harness-init`** — guided interview → spec markdowns → `bootstrap.sh` automatically.
- **Codex CLI (optional)** — multi-turn dialogue, `gpt-image-2` logo / UI mocks. `engineer` / `e2e-reviewer` / `reviewer` independently delegable to Codex (`USE_CODEX_<ROLE>`).
- **One-command bootstrap** — bare git + `dev`/`stage`/`main` worktrees + Husky + Biome + Nix flake + 9 GitHub Actions + Drizzle + Resend + Playwright + Maestro.
- **Per-platform framework choice** — Web (`nextjs`/`tanstack`), iOS (`swift`/`expo`/`flutter`), Android (`kotlin`/`expo`/`flutter`), Desktop (`tauri`/`electron` × macOS/Windows/Linux), Backend (`hono`/`gin`/`rust`), DB (`d1`/`postgres`/`mysql`/`sqlite`). Independent choices.
- **Parallel lanes via Agent Teams** — `/harness-team-lead` runs up to `MAX_LANES` (1..4, default 4) lanes × 4 roles. Lanes added one at a time after a per-lane RAM/swap/compressor check (`spawn-lane-decision.sh`). After each PR the lane's four teammates `/clear`. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.
- **Automatic secret masking** — `UserPromptSubmit` hook runs every prompt through `mask-secrets.sh` (9 patterns) before writing to `dev/docs/talk/<date>.md`.
- **5 lazy-loaded skills, one rule set** — TDD / Hono Clean Arch / Drizzle migrate-only / Nix-pure / design / JSDoc / no-hardcoded-secrets, all in `rules/*.md` and shared verbatim across Claude / Codex / Cursor / Aider.

## Installation

Prerequisites — Claude Code (latest), and **either** (a) Nix installed (recommended; `nix develop` / `direnv allow` provides `codex`, `rtk`, `python+SDK`, `jq`, `bash`, `git`), **or** (b) `git` / `bash` / `jq` / `direnv` / `python3.12+` plus `codex` (`npm install -g @openai/codex`) and `rtk` (`brew install rtk`) installed yourself. Either way, one-time `codex login` is required (ChatGPT subscription).

Fresh-machine setup with Nix:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
git clone https://github.com/kirinnokubinagai/my-harness-generator
cd my-harness-generator
direnv allow                 # or `nix develop`
codex login
```

Platforms: macOS (arm64/x86_64), Linux (x86_64/aarch64), Windows via WSL2. First `nix develop` on macOS arm64 may compile `codex` from source (~20–60 min); subsequent enters are instant. The harness routes lane Codex calls through a shared `codex app-server` daemon (`harness-codex-daemon` skill).

Then in Claude Code:

```
/plugin marketplace add https://github.com/kirinnokubinagai/my-harness-generator
/plugin install my-harness@my-harness-generator
```

Restart Claude Code (or `/clear`) so the new skills and hooks load. Verify with `/my-harness-init` — if the first question appears, the install is good. `Esc` aborts without creating anything.

## Quick start

`/my-harness-init` is the only command you need to start a new project. The first question chooses English or Japanese; everything generated afterward follows. The interview is one question per turn, with masked Q&A auto-saved to `dev/docs/spec/` and `dev/docs/talk/`. Order is deliberate: deep discovery → structural shape → features → **mocks before tools** → data model.

| # | Phase | What you decide |
|---|---|---|
| 0 | Language | EN or JA for the rest of the interview |
| 1 | Setup | Project root, AI helpers (Claude / Claude + Codex), global CLAUDE.md handling, task tracking (markdown / GitHub Issues), `MAX_LANES` (1..4) |
| 2 | Discovery | Open conversation — failure modes, pushback, scale, trust, differentiation, day-2 ops |
| 3 | Structure | Architecture (client-server / serverless / pure P2P / hybrid P2P) + platforms |
| 4 | Features | Whole-project feature list drilled per feature (access / failure / observability / latency budget / etc) |
| 5 | Visual | Logo (3) + 3–5 UI mocks per platform via Codex `gpt-image-2`; drill after each |
| 6 | Tools | Framework / backend / DB / package manager / email / E2E / Claude Code Action — referencing the approved mocks |
| 7 | Data model | Entities + relationships + PII (mermaid ER); drilled per entity |
| 8 | Bootstrap | Cross-check, run `bootstrap.sh`, generate initial issues / task files |

After bootstrap, **exit and restart Claude inside `dev/`** (no documented way to reload CLAUDE.md / settings mid-session):

```bash
# Ctrl+D or /exit, then:
cd ~/<project>/dev && claude
direnv allow
nix develop --command pnpm install
nix develop --command pnpm exec husky
nix develop --command pnpm exec vitest run    # health.test.ts green

git remote add origin git@github.com:<owner>/<repo>.git
git push --all origin
bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>
```

## Lifecycle & daily commands

| Phase | Activity | Command |
|---|---|---|
| Spec → Design → Tasks | Interview → mocks → tool selection → bootstrap | `/my-harness-init` |
| Switch session | Restart in `<root>/dev/` so project-scope CLAUDE.md / settings load | `cd <root>/dev && claude` |
| Implementation | Parallel lanes — issues dispatched to idle lanes by file ownership | `/harness-team-lead` |
| Deploy | First run generates Alchemy v2 infra + Secrets; subsequent runs stage dev → stage → main (ZAP / Playwright / Maestro / canary 10% → 100%) | `/harness-deploy` |
| Adopt existing repo / refresh after plugin update | Idempotent — auto-detects `.bare/` | `/my-harness-adopt` |
| Live lane view | Separate terminal | `bash <plugin>/scripts/monitor-agents.sh <project-root>` |
| Watchdog mode | Lead consumes in Step 3.0 | `bash <plugin>/scripts/monitor-agents.sh <project-root> --watchdog` |

Hotfixes by hand: branch `hotfix/<short>` from `main`, PR to `main`, merge-commit back to `stage`/`dev`. See `docs/HOTFIX.md`.

## Conventions (single source of truth)

All harness conventions live in `rules/*.md` and are loaded automatically by every entry point — embedded in `dev/CLAUDE.md` + `dev/AGENTS.md` (Claude / Codex / Cursor / Aider read these natively), and auto-attached to Codex via `codex-ask.sh --role`. No per-rule slash command — the rules are always in scope.

| File | Enforces |
|---|---|
| `rules/tdd.md` | Red / Green / Refactor; AAA; `$LANG` test names |
| `rules/hono-clean-arch.md` | 4-layer Clean Architecture; strict dependency direction |
| `rules/drizzle.md` | Drizzle migrate-only; `drizzle-kit push` prohibited |
| `rules/nix-pure.md` | Tool invocations via the per-worktree devshell; `brew install` forbidden |
| `rules/design.md` | Lucide Icons only; no AI-style gradients; WCAG AA |
| `rules/jsdoc.md` | TSDoc on every export; no inline comments inside functions |
| `rules/no-hardcoded-secrets.md` | env vars / SOPS only; gitleaks at pre-commit |

## Slash commands

- `/my-harness-init` — start a new project (one-time per project; resumes from `.my-harness/init-state.json`).
- `/my-harness-adopt` — idempotent. First run converts an existing git repo (history preserved); subsequent runs refresh `dev/.my-harness/` and regenerate `dev/CLAUDE.md` / `dev/AGENTS.md`. Non-destructive on the refresh path.
- `/harness-team-lead` — parallel-lane orchestration.
- `/harness-deploy` — idempotent; setup on first run, staged release after.
- `/harness-codex-daemon` — start/stop the shared `codex app-server` daemon.

## Generated layout

```
<project>/
├── .bare/                              bare git
├── .git → .bare
├── .my-harness/.config                 selected options (committed)
├── .my-harness/codex-sessions/         Codex session IDs (gitignored)
├── dev/   stage/   main/               worktrees (work in dev)
├── lanes/feat-<n>-<slug>/              feature worktrees (≤ MAX_LANES)
└── lanes/hotfix-<n>-<slug>/            hotfix worktrees
    ├── .claude/CLAUDE.md               project conventions
    ├── dev/.claude/                    when USE_GLOBAL_CLAUDE=no (claudeMdExcludes)
    ├── docs/{spec,design,talk,task}/   spec / mocks / Q&A logs / tasks
    ├── .my-harness/                    plugin runtime (rsynced)
    ├── flake.nix .envrc                Nix-pure environment
    ├── biome.json package.json         dev tooling
    ├── .husky/                         pre-commit / pre-push / commit-msg
    └── .github/workflows/              9 CI workflows
```

## Branch policy

| from → to | requirement |
|---|---|
| `feat/*` → `dev` | PR + format / lint / test / typecheck pass |
| `dev` → `stage` | Human approval + OWASP ZAP + Playwright + Maestro + Semgrep + Trivy |
| `stage` → `main` | Human approval + all gates + canary 10% → 100% |
| `hotfix/*` → `main` | Emergency approval + minimal gates (post-merge ZAP / E2E) |

Direct push to `main` / `stage` is blocked locally (pre-push) and remotely (branch protection). Apply protection once: `bash scripts/setup-branch-protection.sh <owner>/<repo>`.

## Configuration

The interview writes `<root>/.my-harness/.config`. Re-run non-interactively with `bash bootstrap.sh <root> --config <root>/.my-harness/.config`. Relevant keys: `LANG`, `PROJECT_NAME`, `USE_<PLATFORM>`/`<PLATFORM>_KIND` per platform, `USE_BACKEND`/`BACKEND_KIND`, `USE_DB`/`DB_KIND`, `USE_EMAIL`, `USE_PLAYWRIGHT`, `USE_MAESTRO`, `USE_CLAUDE_ACTION`, `CLAUDE_AUTH`, `USE_GITHUB_ISSUES`, `USE_GLOBAL_CLAUDE`, `USE_CODEX_*` (per role), `ON_CODEX_AUTH_FAIL` (`pause`/`fail`), `PACKAGE_MANAGER`, `ARCHITECTURE`, `MAX_LANES` (1..4), `HARNESS_LANE_RAM_MB` / `HARNESS_LANE_SWAP_MAX_MB` / `HARNESS_LANE_COMP_MAX_MB` (per-lane gate thresholds).

## Troubleshooting

| Symptom | Fix |
|---|---|
| Skill doesn't fire | Restart Claude Code or `/clear` |
| Hook doesn't write to `dev/docs/talk/` | Confirm `~/.claude/settings.json` has the plugin's `UserPromptSubmit` + `Stop` hooks; `/doctor` |
| Codex auth error | `codex login` |
| Lane paused with `blocked-codex-auth` | `codex login` then say "resume" — same session preserved server-side |
| `subscription-or-quota` | Renew ChatGPT, or set `USE_CODEX_<ROLE>=no` in `.my-harness/.config`, then "resume" |
| Hotfix back-merge conflict | `git merge --no-ff`; never `rebase` / `reset --hard` / `push --force` |
| Accidentally ran `drizzle-kit push` | revert → `drizzle-kit generate --name <descriptive>` → `wrangler d1 migrations apply` |
| Update plugin | `/plugin marketplace update` → `/plugin install my-harness@my-harness-generator` |

## FAQ

**Add to an existing project?** Use `/my-harness-adopt`. It handles the bare-git swap when there's no `.bare/` yet (destructive on the worktree layout, history preserved).

**Is Codex required?** No — pick `n` at Setup and Claude runs everything solo (only image generation is skipped).

**What does "parallel lanes" actually do?** `harness-team-lead` partitions issues across lanes by file ownership (no two lanes touch the same files). Each lane runs analyst → engineer → e2e-reviewer → reviewer in its own worktree. See [`docs/WORKFLOW.md`](./docs/WORKFLOW.md).

**Will `dev/docs/talk/` end up in my repo?** Yes (private repo recommended). `mask-secrets.sh` redacts secrets; add `dev/docs/talk/` to `.gitignore` if you'd rather not commit conversational content.

**Isolate from `~/.claude/CLAUDE.md`?** Pick `USE_GLOBAL_CLAUDE=no` at Setup — the plugin writes `dev/.claude/settings.json` with `claudeMdExcludes` listing your absolute global CLAUDE.md path. Managed-policy CLAUDE.md (org-deployed) cannot be excluded by project settings.

## Detailed docs

- Production guide: [`docs/PRODUCTION.md`](./docs/PRODUCTION.md)
- Workflow: [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)
- Hotfix: [`docs/HOTFIX.md`](./docs/HOTFIX.md)
- Setup + Security: [`docs/SETUP.md`](./docs/SETUP.md)
- Infrastructure: [`docs/INFRA.md`](./docs/INFRA.md)
- iOS DAST: [`docs/IOS_DAST.md`](./docs/IOS_DAST.md)
- Engineering conventions: `rules/*.md` (including `rules/production.md`)

## Contributing

PRs welcome. **Do not `git clone` this repo to use the plugin** — install via `/plugin marketplace add <github-url>` so updates flow through `/plugin marketplace update`. To contribute: fork → add your fork as a local marketplace → edit / push → `/plugin marketplace update` to test → PR back. All shell scripts must pass `bash -n`; every `SKILL.md` requires front-matter `name` + `description`; commits follow Conventional Commits with a Japanese body.

## License

MIT — see [`LICENSE`](./LICENSE).
