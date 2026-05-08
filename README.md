# my-harness-generator

> A Claude Code plugin that turns "I have a vague idea" into a fully scaffolded, production-ready project — in one conversation.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-orange.svg)](https://code.claude.com)
[![日本語](https://img.shields.io/badge/lang-日本語-red.svg)](./README.ja.md)

[日本語版はこちら / Japanese version](./README.ja.md)

---

## What it does

Most starter kits give you boilerplate but leave the hard parts — requirements discovery, architecture decisions, lane assignment, security discipline — entirely to you. This plugin runs a structured interview with you, optionally consults OpenAI Codex for second opinions, generates branding (logo + UI mocks), settles the tech stack, and produces a fully wired-up monorepo with branch protection, CI, git hooks, and 4-lane parallel-development conventions — all from a single slash command.

The result on disk is a project where:

- The first commit is already green (CI, tests, lints all pass).
- Branch protection is applied to `main` / `stage` / `dev` and direct push is impossible.
- Every conversation you have with Claude is auto-logged (with secrets masked) into `dev/docs/talk/`.
- The next step is always documented — you never have to wonder "what now?".

## Highlights

- **`/my-harness-init`** — guided interview that produces spec markdowns and runs the bootstrap automatically.
- **Codex CLI integration (optional)** — multi-turn dialogue with session resume; logo and UI-mock generation via `gpt-image-2`. Optionally delegate `engineer` / `e2e-reviewer` / `reviewer` subagent roles to Codex per role (independent toggles, master switch via `USE_CODEX`).
- **One-command bootstrap** — bare git + `dev`/`stage`/`main` worktrees + Husky + Biome + Nix flake + 9 GitHub Actions workflows + Drizzle + Resend + Playwright + Maestro.
- **Per-platform framework choice** — Web (`nextjs` or `tanstack`), iOS (`swift` / `expo` / `flutter`), Android (`kotlin` / `expo` / `flutter`), Desktop (`tauri` or `electron` + macOS/Windows/Linux), Backend (`hono` / `gin` / `rust`), DB (`d1` / `postgres` / `mysql` / `sqlite`). Each platform's framework choice is independent.
- **4-lane parallel development** — `harness-team-lead` agent assigns issues across 4 independent lanes (analyst → engineer → e2e-reviewer → reviewer per lane).
- **Automatic secret masking** — `UserPromptSubmit` hook runs every prompt through `mask-secrets.sh` (9 patterns) before writing to `dev/docs/talk/<date>.md`.
- **21 skills, lazy-loaded** — TDD, Hono Clean Architecture, Drizzle migrate-only, Nix-pure execution, design discipline, JSDoc, git discipline, hardcoded-secret prevention, and more.
- **GitHub-Issue mode toggle** — choose between `gh issue create` and local `dev/docs/task/*.md` files at init time.

## Installation

### Prerequisites

- Claude Code (latest)
- `git`, `bash`, `jq`, and `direnv` (for Nix dev shell auto-activation)
- Optional: Codex CLI for AI-assisted design and second-opinion reviews. Install with `npm install -g @openai/codex` and log in once with `codex login` (requires a ChatGPT subscription).

### Install the plugin

In Claude Code:

```
/plugin marketplace add https://github.com/kirinnokubinagai/my-harness-generator
/plugin install my-harness@my-harness-generator
```

Then **fully restart Claude Code** (or run `/clear`) so the new skills and hooks load.

### Verify

```
/my-harness-init
```

The interview should start. If the first question appears, the plugin is installed correctly. Press `Esc` (or close the conversation) to abort the interview without creating anything.

## Quick start

The first question of `/my-harness-init` asks whether to use English or Japanese; everything generated afterward follows that choice.

`/my-harness-init` is the only command you need to start a new project. It walks through the following 9 phases — one question per turn, with masked Q&A automatically saved to `dev/docs/spec/` and `dev/docs/talk/`. The order is deliberate: deep discovery → structural shape → features → **mocks before tools** (so we pick the framework / DB / package manager from what the screens actually need) → data model:

| # | Phase | What you decide |
|---|-------|-----------------|
| 0 | **Language** | English or Japanese for the rest of the interview |
| 1 | **Setup** | Project root path, Codex y/n, global CLAUDE.md inheritance, task management mode (GitHub Issues or local files) |
| 2 | **Discovery** | Open multi-turn conversation that drills into failure modes, who'd push back, scale breakpoints, trust model, differentiation, day-2 ops — the load-bearing constraints |
| 3 | **Structure** | Just architecture (client-server / serverless / pure P2P / hybrid P2P) and platform multi-select (web / desktop / mobile + iOS-or-Android) |
| 4 | **Features** | Complete feature list for the whole project — everything needed before you'd call it done — drilled per feature on access path / failure / observability / onboarding / power-user / empty / failure-recovery / latency budget |
| 5 | **Visual** | Logo (3 variants) plus 3–5 UI mocks per chosen platform via Codex `gpt-image-2`; after each mock, drill on missing elements / confusing elements / hidden constraints. Mocks become source of truth |
| 6 | **Tools** | Framework (per platform), backend, DB, package manager, email, E2E, Claude Code Action — every prompt references the approved mocks ("your dashboard mock needs realtime, so …") |
| 7 | **Data model** | Entities, relationships, PII handling (mermaid ER diagram) — drilled per entity on lifecycle / GDPR / permissions / cardinality / migration |
| 8 | **Bootstrap** | Cross-check the spec, run `bootstrap.sh`, generate initial issues / task files (one per lane) |

After bootstrap completes, **exit the current Claude session and restart inside `dev/`** — Claude Code has no documented way to change the working directory and reload `CLAUDE.md` / `settings.json` mid-session. The generated `start-dev.sh` launcher does this in one step:

```bash
# Step 1: exit the current Claude session (Ctrl+D or /exit)
# Step 2: in your terminal:
~/<project>/start-dev.sh   # launches `claude` rooted at <project>/dev/
# or equivalently:  cd ~/<project>/dev && claude
```

Then inside the new session:

```bash
direnv allow
nix develop --command pnpm install
nix develop --command pnpm exec husky
nix develop --command pnpm exec vitest run    # health.test.ts should be green
```

Push to GitHub:

```bash
git remote add origin git@github.com:<owner>/<repo>.git
git push --all origin
bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>
```

## Project lifecycle

The plugin enforces a 6-phase flow from idea to production. The first three phases all live inside `/my-harness-init`; phases four through six each have their own command.

| Phase | Activity | Primary command |
|-------|----------|-----------------|
| 1. Spec | Discovery + features + data model | `/my-harness-init` (Discovery → Features phases; data model lands after mocks) |
| 2. Design | Logo + per-platform UI mocks + spec iteration; mocks then drive tool selection | `/my-harness-init` (Visual phase, then Tools phase) |
| 3. Tasks | Issues / task files generated, file-ownership assigned to 4 lanes, bootstrap runs | `/my-harness-init` (Bootstrap phase) |
| 3.5. Switch session | Restart Claude Code inside `<root>/dev/` so project-scope CLAUDE.md and settings load | `<root>/start-dev.sh` |
| 4. Implementation | 4-lane parallel feature work; each issue runs in a fresh subagent context | `/harness-new-feature <issue>` |
| 5. Deploy setup | Terraform infra (Cloudflare D1 / R2 / Pages), wrangler bindings, GitHub secrets / vars, fastlane (iOS) | `/harness-deploy-setup` |
| 6. Deploy | `dev` → `stage` (auto + human label) → `main` (canary 10% → 100%) | `/harness-deploy-execute` |

A separate emergency path (`/harness-new-hotfix`) exists for production fixes; see "Daily commands" below.

## Daily commands

After init, these are the slash commands you'll reach for most often:

| What you want | Command |
|---------------|---------|
| Start a new feature in a 4-lane parallel worktree | `/harness-new-feature <issue#> <slug>` |
| Emergency hotfix (branched from `main`) | `/harness-new-hotfix <issue#> <slug>` |
| Resolve a conflict (merge-commit only — no rebase) | `/harness-resolve-conflict` |
| Sync all feature branches with `dev` after a hotfix back-merge | `/harness-sync-features` |
| Ask Codex for a second opinion | `/harness-codex-consult` (or just say "ask Codex") |
| Manual secret scan | `/harness-check-secrets` |
| Apply branch protection in bulk | `/harness-branch-protection` |
| Generate Terraform deploy infrastructure | `/harness-deploy-setup` |
| Run a staged production deploy | `/harness-deploy-execute` |

## Auto-firing skills

These convention skills load automatically when you do certain things — you don't have to invoke them:

| Skill | When it fires |
|-------|---------------|
| `harness-tdd` | Writing tests, fixing bugs, refactoring, behavior changes |
| `harness-hono-clean-arch` | Implementing Hono routes, services, repositories |
| `harness-drizzle-rules` | Schema changes or migrations (enforces migrate-only, blocks `drizzle-kit push`) |
| `harness-nix-pure` | Running commands or installing tools (forbids `brew install`, requires `nix develop --command`) |
| `harness-design-rules` | UI components, color choices, icon usage (Lucide only, no AI-style gradients) |
| `harness-jsdoc` | Writing functions, types, comments (JSDoc/TSDoc required, no inline comments inside functions) |
| `harness-git-discipline` | Git operations and conflicts (no `rebase` / `reset --hard` / `push --force`) |
| `harness-no-hardcoded-secrets` | Working with env vars, API keys, `.env` files |
| `harness-mask` | Manually masking sensitive content before logging |
| `harness-codex-consult` | "Ask Codex …" / second-opinion flows |

## Slash commands

**Two slash commands you'll use directly:**

- `/my-harness-init` — start a new project (one-time, per project). Detects existing `.my-harness/init-state.json` and resumes from the saved phase.
- `/harness-team-lead` — coordinate ongoing 4-lane parallel implementation

Plus 19 convention skills that load automatically when relevant (TDD, JSDoc, Hono Clean Architecture, Drizzle, Nix-pure, design rules, secret masking, git discipline, etc.). You don't invoke these directly — agents pull them in by topic.

## Architecture

```
[user input]
    ↓
[UserPromptSubmit hook] → mask-secrets.sh → dev/docs/talk/<date>.md
    ↓
[Claude]
    ↓ lazy-load
[harness-* skill]  (auto-selected from 21)
    ↓
[shell script]
    ↓
[implementation]
    ↓
[Stop hook] → extract assistant response → mask → dev/docs/talk/
    ↓
[git pre-commit] → gitleaks + check-forbidden-patterns (double defense)
    ↓
[push]
```

## Generated project structure

```
<project>/
├── .bare/                              bare git repo
├── .git → .bare                        gitfile pointing to .bare
├── .my-harness/.config                 selected options (team-shared, in git)
├── .my-harness/codex-sessions/         Codex session IDs (gitignored)
├── dev/   stage/   main/               worktrees (you only work in dev)
├── lanes/feat-<n>-<slug>/              feature worktrees (up to 4 in parallel)
└── lanes/hotfix-<n>-<slug>/            main-based hotfix worktrees
    ├── .claude/CLAUDE.md               always written; project conventions go here.
    ├── dev/.claude/                    only when USE_GLOBAL_CLAUDE=no (writes settings.json with claudeMdExcludes for ~/.claude/CLAUDE.md)
    ├── docs/{spec,design,talk,task}/   spec / mocks / Q&A logs / tasks
    ├── .my-harness/                    plugin runtime files (copied)
    ├── flake.nix .envrc                Nix-pure environment
    ├── biome.json package.json         dev tooling
    ├── .husky/                         pre-commit / pre-push / commit-msg
    └── .github/
        ├── workflows/                  9 CI workflows
        └── scripts/maybe-create-issue.js   GitHub-Issue branching helper
```

## Branch policy

| from → to | requirement |
|-----------|-------------|
| `feat/*` → `dev` | PR + format / lint / test / typecheck pass |
| `dev` → `stage` | Human approval + OWASP ZAP + Playwright + Maestro + Semgrep + Trivy pass |
| `stage` → `main` | Human approval + all gates green + canary 10% → 100% |
| `hotfix/*` → `main` | Emergency approval + minimal test/lint/format (post-merge ZAP / E2E runs immediately) |

Direct pushes to `main` and `stage` are blocked twice: by the local pre-push hook and by GitHub branch protection (applied via `/harness-branch-protection`).

## Conventions enforced

- **TDD strict** — Red-Green-Refactor cycle. Production code written without a failing test first must be deleted and rewritten.
- **Hono Clean Architecture** — `domain ← application ← infrastructure / interfaces`, dependency direction enforced.
- **Drizzle migrate-only** — `drizzle-kit push` is forbidden (no migration history, no rollback).
- **Nix pure** — all tooling via `nix develop --command`. `brew install` is forbidden.
- **No AI-look design** — Lucide Icons only; no gradients, neon, or emoji; WCAG AA; the 10 essential UX-psychology principles required.
- **JSDoc / TSDoc required** — on every export; no inline comments inside functions; descriptions in Japanese (project default).
- **Git discipline** — no `rebase`, `reset --hard`, or `push --force`. Conflicts are resolved with merge commits.

## Fresh-agent-per-issue principle

Every issue is processed in a brand-new subagent context. `harness-team-lead` always spawns engineer / analyst / e2e-reviewer / reviewer agents via `Task(subagent_type=..., prompt=...)`, never via `SendMessage` continuation. This guarantees:

- No bleed-over of decisions or naming choices from previous issues.
- No accumulating context cost as the project grows.
- Each lane stays truly independent — what happens in lane 2 cannot influence lane 3.

When the orchestrating session itself becomes heavy (after 5–10 issues), `harness-team-lead` saves progress to `.my-harness/team-state.json` and asks you to `/clear` and resume from that file.

## Configuration

The interview produces `<root>/.my-harness/.config`:

```bash
LANG=en
PROJECT_NAME=todo-app
USE_WEB=yes
WEB_KIND=nextjs               # only when USE_WEB=yes (nextjs | tanstack)
USE_IOS=no
IOS_KIND=swift                # only when USE_IOS=yes (swift | expo | flutter)
USE_ANDROID=no
ANDROID_KIND=kotlin           # only when USE_ANDROID=yes (kotlin | expo | flutter)
USE_DESKTOP=no
DESKTOP_KIND=tauri            # only when USE_DESKTOP=yes (tauri | electron)
DESKTOP_OS=macos,windows,linux  # only when USE_DESKTOP=yes
USE_BACKEND=yes
BACKEND_KIND=hono             # only when USE_BACKEND=yes (hono | gin | rust)
USE_DB=yes
DB_KIND=d1                    # only when USE_DB=yes (d1 | postgres | mysql | sqlite)
USE_EMAIL=yes                 # Resend + password-reset flow
USE_PLAYWRIGHT=yes
USE_MAESTRO=no
USE_CLAUDE_ACTION=yes         # PR review via Claude Code Action
CLAUDE_AUTH=oauth             # or "api"
USE_GITHUB_ISSUES=yes         # or "no" → docs/task/*.md
USE_GLOBAL_CLAUDE=yes         # or "no" → writes dev/.claude/settings.json with claudeMdExcludes for ~/.claude/CLAUDE.md
CODEX_SESSION=my-harness-init
USE_CODEX_ENGINEER=yes        # delegate engineer subagent work to Codex (only when USE_CODEX=yes)
USE_CODEX_E2E_REVIEWER=no     # delegate E2E test report synthesis to Codex (default: no — Claude runs locally)
USE_CODEX_REVIEWER=yes        # delegate convention review to Codex
ON_CODEX_AUTH_FAIL=pause      # default: pause + user notify + resume after re-login. "fail" → immediate fail
PACKAGE_MANAGER=pnpm          # pnpm | bun | npm | yarn — drives install/exec lines, flake.nix, husky, CI
ARCHITECTURE=client-server    # client-server | client-serverless | p2p-pure | p2p-hybrid
                              # p2p-pure skips backend bootstrap; p2p-hybrid keeps a lightweight coordinator
```

You can re-run bootstrap non-interactively:

```bash
bash bootstrap.sh <root> --config <root>/.my-harness/.config
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Skill doesn't fire | Restart Claude Code or `/clear` |
| Hook doesn't write to `dev/docs/talk/` | Confirm `~/.claude/settings.json` has the plugin's `UserPromptSubmit` and `Stop` hooks; run `/doctor` to validate the schema |
| Codex returns auth error | `/harness-check-codex-auth`, then `codex login` |
| Codex subagent paused with `blocked-codex-auth` (login expired mid-flight) | Run `codex login`, then tell team-lead "resume". The same Codex session is preserved on the server. |
| Codex subagent paused with `subscription-or-quota` reason | Renew your ChatGPT subscription, or edit `.my-harness/.config` to set `USE_CODEX_<ROLE>=no` to fall back to Claude for that role. Then say "resume". |
| Conflict during hotfix back-merge | `/harness-resolve-conflict` (never rebase) |
| Accidentally ran `drizzle-kit push` | Revert, then `drizzle-kit generate --name <descriptive>` followed by `wrangler d1 migrations apply` |
| Update plugin | `/plugin marketplace update`, then `/plugin install my-harness@my-harness-generator` |
| Stale worktree refs | `git worktree prune` (bootstrap does this for you) |
| `direnv: error Path 'flake.nix' is not tracked by Git` | `git add flake.nix && git commit` (bootstrap does this for you) |

## FAQ

**Can I add this to an existing project?**
Possible but not recommended. `/my-harness-init` assumes a fresh start. To retrofit, you'd write `.my-harness/.config` by hand and run `bootstrap.sh --config`, but the bare-git swap is destructive.

**Is Codex CLI required?**
No. Pick `n` at the Setup phase and Claude will run all phases solo (only image generation is skipped).

**What does "4-lane parallel" actually do?**
`harness-team-lead` partitions issues across `lane/1` through `lane/4` based on file ownership (no two lanes touch the same files). Each lane runs analyst → engineer → e2e-reviewer → reviewer in its own worktree. See [`docs/WORKFLOW.md`](./docs/WORKFLOW.md).

**Will `dev/docs/talk/` end up in my repo?**
Yes (private repo recommended). `mask-secrets.sh` redacts secrets, but the conversational content itself is committed. Add `dev/docs/talk/` to `.gitignore` if you'd rather not.

**Can I isolate this project from my personal `~/.claude/CLAUDE.md`?**

Yes. Pick `USE_GLOBAL_CLAUDE=no` at Setup. The plugin writes `dev/.claude/settings.json` with `claudeMdExcludes` listing your absolute `~/.claude/CLAUDE.md` path. Claude Code respects this natively — your global instructions are skipped for sessions started in `dev/`. Note: managed-policy CLAUDE.md (org-deployed at `/Library/Application Support/ClaudeCode/CLAUDE.md` etc.) cannot be excluded by individual project settings.

**How do I update the plugin?**
`/plugin marketplace update` then `/plugin install my-harness@my-harness-generator`. Don't `git pull` inside the plugin cache directory.

## Detailed docs

- Workflow: [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)
- Hotfix procedure: [`docs/HOTFIX.md`](./docs/HOTFIX.md)
- Security: [`docs/SECURITY.md`](./docs/SECURITY.md)
- Infrastructure: [`docs/INFRA.md`](./docs/INFRA.md)
- iOS DAST: [`docs/IOS_DAST.md`](./docs/IOS_DAST.md)
- Engineering standards: [`docs/ENGINEER_STANDARDS.md`](./docs/ENGINEER_STANDARDS.md)
- Setup details: [`docs/SETUP.md`](./docs/SETUP.md)

## Contributing

PRs welcome. **Do not `git clone` this repo to use the plugin** — installation is via `/plugin marketplace add <github-url>` so updates flow through `/plugin marketplace update`. Cloning freezes you to that revision.

To contribute changes:

1. Fork on GitHub.
2. Add your fork as a local marketplace from inside Claude Code: `/plugin marketplace add https://github.com/<your-user>/my-harness-generator` and `/plugin install my-harness@my-harness-generator`.
3. Edit your fork directly on GitHub (or via your usual workflow), push, then `/plugin marketplace update` in Claude Code to test.
4. Open a PR back to this repo.

Conventions enforced on the plugin's own code:

- All shell scripts must pass `bash -n` (syntax check).
- Every `SKILL.md` requires a front-matter `name` and `description`.
- Commits follow Conventional Commits with a Japanese body.
- Lane workflow described in [`docs/WORKFLOW.md`](./docs/WORKFLOW.md).

## License

MIT — see [`LICENSE`](./LICENSE).
