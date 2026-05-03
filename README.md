# my-harness-generator

> A Claude Code plugin that turns "I have a vague idea" into a fully scaffolded production-ready project, in one conversation.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-orange.svg)](https://code.claude.com)
[![日本語](https://img.shields.io/badge/lang-日本語-red.svg)](./README.ja.md)

[日本語版はこちら](./README.ja.md)

---

## Why this exists

Most "starter kit" generators give you boilerplate but leave the **hard part** (requirements, architecture, lane assignment, security discipline) on you. This plugin walks Claude through a **7-stage interview** with you, optionally consults OpenAI Codex for second opinions, generates logos, decides the tech stack, and produces a fully wired-up monorepo with branch protection, CI, hooks, and 4-lane parallel-development conventions—all from one slash command.

## Key features

- **`/my-harness-init`**: 7-stage product spec interview → spec markdowns → automated bootstrap
- **Codex CLI integration (optional)**: real multi-turn dialogue with session resume; logo / OG image generation via gpt-image-2
- **One-command bootstrap**: bare git + dev/stage/main worktrees + Husky + Biome + Nix flake + 9 GitHub Actions workflows + Hono + Drizzle + Resend + Playwright + Maestro
- **4-lane parallel development** with role-based agents (analyst → engineer → e2e-reviewer → reviewer × 4)
- **Automatic secret masking**: `UserPromptSubmit` hook captures every prompt, runs it through `mask-secrets.sh` (9 patterns), writes to `dev/docs/talk/<date>.md`
- **20 skills, lazy-loaded**: TDD, Hono Clean Architecture, Drizzle migrate-only, Nix pure execution, design discipline, JSDoc, git rules, hardcoded-secret prevention, etc.
- **Optional GitHub Issue mode**: switch between `gh issue create` and local `docs/task/*.md` files

## Installation

### Prerequisites

- Claude Code (latest)
- `git`, `bash`, `jq`, `direnv` (for Nix dev shell auto-activation)
- (Optional) `npm install -g @openai/codex` and `codex login` if you want Codex consultations

### Install the plugin

In Claude Code, run:

```
/plugin marketplace add https://github.com/kirinnokubinagai/my-harness-generator
/plugin install my-harness@my-harness-generator
```

Then **fully restart Claude Code** (or run `/clear`) so the new skills and hooks are loaded.

### Verify

```
/my-harness-generator
```
The top-level skill should respond with a description of all available commands.

## Quick start (5 minutes)

```
/my-harness-init
```

Claude will ask you, one at a time:

1. **Project root directory** (default: `~/<project-name>`)
2. **Project name** (slug, lowercase + hyphens)
3. **Use Codex integration?** (y/n)
4. (If yes) Codex login check + session name
5. **Task management mode?** (`y` = GitHub Issues, `n` = local `docs/task/`)
6. **Inherit your global Claude settings?** (y = use `~/.claude/CLAUDE.md`, n = isolate)

Then you'll go through 7 stages:

| Stage | Topic | Output |
|-------|-------|--------|
| 1 | Problem definition | `dev/docs/spec/01-problem.md` |
| 2 | Personas / users | `dev/docs/spec/02-personas.md` |
| 3 | Features / MVP boundary | `dev/docs/spec/03-features.md` |
| 4 | Tech stack | `dev/docs/spec/04-stack.md` + `.my-harness/.config` |
| 5 | Data model | `dev/docs/spec/05-data-model.md` (with mermaid ER) |
| 6 | Visual / branding | `dev/docs/spec/06-visual.md` + `dev/docs/design/logo-*.png` |
| 7 | Final review + bootstrap | runs `bootstrap.sh --config .my-harness/.config` |

Every Q&A turn is auto-saved (masked) to `dev/docs/talk/<date>.md` via the `UserPromptSubmit` hook.

After bootstrap completes:

```bash
cd ~/<project-name>/dev
direnv allow
nix develop --command pnpm install
nix develop --command pnpm exec husky
nix develop --command pnpm exec vitest run    # health.test.ts should be green
```

Then push to GitHub:

```bash
git remote add origin git@github.com:<owner>/<repo>.git
git push --all origin
bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>
```

## Detailed usage

### Working on a feature (4-lane parallel)

```
/harness-new-feature 42 user-login
```

This invokes `harness-new-feature` skill which calls `new-feature.sh 42 user-login`, creating `lanes/feat-42-user-login/` worktree from `dev`. Move into it:

```bash
cd lanes/feat-42-user-login
direnv allow
```

Now write a failing test first (the `harness-tdd` skill auto-fires when you mention "tests"):

```ts
// src/auth/login.test.ts
import { describe, expect, it } from 'vitest';
import { login } from './login';

describe('login', () => {
  it('rejects empty email', async () => {
    const result = await login({ email: '', password: 'x' });
    expect(result.error).toBe('email is required');
  });
});
```

Run it (must fail first):
```bash
nix develop --command pnpm exec vitest related --run src/auth/login.test.ts
```

Implement minimal code to pass, then commit. Husky pre-commit runs Biome / vitest / tsc / gitleaks / forbidden-pattern-check.

```bash
git add -A
git commit -m "feat(auth): メールアドレス必須バリデーション"
git push origin feat/42-user-login
gh pr create --base dev --title "feat(#42): user login"
```

CI runs `pr-to-dev.yml` (quality + e2e + claude-review + auto-merge).

### Asking Codex for a second opinion

```
/harness-codex-consult
```

Or just talk: "Codex に聞いてください、Hono の middleware 順序として A→B→C と B→A→C どちらが正しいか"

Claude calls `codex-ask.sh --role architect ...` with auto-resolved session (set up at /my-harness-init stage 0). Codex remembers all previous stages.

### Generating a logo

In stage 6 of `/my-harness-init`, or any time:

> "todo-app のロゴを 3 案、ミニマル / ベクター / 主色 #14b8a6 で `dev/docs/design/logo-{1,2,3}.png` に保存して"

Claude invokes `harness-codex-consult` with `role: designer`. Codex (which has gpt-image-2 access) generates and saves the PNGs. **No special flags needed**—it's just a normal request.

### Hotfix flow

```
/harness-new-hotfix 99 critical-auth-bypass
```

Creates `lanes/hotfix-99-critical-auth-bypass/` from `main` (not dev). After merge to main:
- `post-merge-hotfix.yml` runs OWASP ZAP / MobSF immediately
- Auto back-merges main → stage → dev with **merge commits** (no rebase)

### Resolving conflicts

**Never use `git rebase` / `git reset --hard` / `git push --force`**. Use:

```
/harness-resolve-conflict
```

Which calls `resolve-conflict.sh` that does `git merge --no-ff` only.

### Syncing all features after a hotfix back-merge

```
/harness-sync-features
```

Runs `sync-features-with-dev.sh` which iterates `lanes/feat-*` and merges `origin/dev` into each via `git merge --no-ff`.

## Available skills

### Top-level (2)
| Skill | Trigger |
|-------|---------|
| `my-harness-generator` | "harness について" / "ハーネス更新" |
| `my-harness-init` | New project from scratch |

### Convention skills (10, lazy-load)
| Skill | When it fires |
|-------|--------------|
| `harness-tdd` | Writing tests, fixing bugs, refactoring |
| `harness-hono-clean-arch` | Implementing Hono routes, services, repositories |
| `harness-drizzle-rules` | Schema changes, migrations |
| `harness-nix-pure` | Running commands, installing tools |
| `harness-design-rules` | UI components, colors, icons |
| `harness-jsdoc` | Writing functions, types, comments |
| `harness-git-discipline` | Git operations, conflicts |
| `harness-no-hardcoded-secrets` | env vars, API keys, `.env` |
| `harness-mask` | Manual secret masking |
| `harness-codex-consult` | "Codex に聞いて", second opinions |

### Shell-wrapping skills (8)
| Skill | Wraps |
|-------|-------|
| `harness-new-feature` | `new-feature.sh` |
| `harness-new-hotfix` | `new-hotfix.sh` |
| `harness-resolve-conflict` | `resolve-conflict.sh` |
| `harness-sync-features` | `sync-features-with-dev.sh` |
| `harness-check-codex-auth` | `check-codex-auth.sh` |
| `harness-check-secrets` | `check-forbidden-patterns.sh` |
| `harness-setup-secrets` | `setup-secrets.sh` |
| `harness-branch-protection` | `setup-branch-protection.sh` |

## Architecture

```
[user input]
    ↓
[UserPromptSubmit hook] → mask-secrets.sh → dev/docs/talk/<date>.md
    ↓
[Claude]
    ↓ lazy load
[harness-* skill] (auto-selects from 20)
    ↓ skill instructs
[shell script]
    ↓
[implementation]
    ↓
[Stop hook] → extract assistant response → mask → talk/
    ↓
[git pre-commit] → gitleaks + check-forbidden-patterns (double defense)
    ↓
[push]
```

## Generated project structure

```
<project>/
├── .bare/                              bare git
├── .git → .bare                        gitfile pointing to .bare
├── .my-harness/.config                 selected options (team-shared, in git)
├── .my-harness/codex-sessions/         Codex session IDs (gitignored)
├── dev/   stage/   main/               worktrees (only work in dev)
├── lanes/feat-<n>-<slug>/              feature worktrees (4 parallel)
├── lanes/hotfix-<n>-<slug>/            hotfix worktrees (main-based)
└── dev/                                main work area
    ├── .claude/                        if USE_GLOBAL_CLAUDE=no
    ├── docs/{spec,design,talk,task}/   spec / mocks / Q&A logs / tasks
    ├── .my-harness/                    plugin runtime files (copied)
    ├── flake.nix .envrc                Nix pure environment
    ├── biome.json package.json         dev tooling
    ├── .husky/                         pre-commit / pre-push / commit-msg
    └── .github/
        ├── workflows/                  9 CI workflows
        └── scripts/maybe-create-issue.js  GitHub Issue branching helper
```

## Branch policy

| from → to | requirement |
|-----------|-------------|
| `feat/*` → `dev` | PR + format/lint/test/typecheck pass |
| `dev` → `stage` | Human approval + OWASP ZAP + Playwright + Maestro + Semgrep + Trivy pass |
| `stage` → `main` | Human approval + all gates green + canary 10% → 100% |
| `hotfix/*` → `main` | Emergency approval + minimal test/lint/format (post-merge ZAP/E2E) |

Direct push to `main` and `stage` is blocked by both pre-push hook and GitHub branch protection (`harness-branch-protection` skill applies the latter).

## Convention enforcement (skills handle these)

- **TDD strict**: Red-Green-Refactor; deleting code that was written before tests
- **Hono Clean Architecture**: domain ← application ← infrastructure / interfaces, with strict dependency direction
- **Drizzle migrate only**: `drizzle-kit push` is forbidden
- **Nix pure**: all tooling via `nix develop --command`; `direnv allow` automates this
- **No AI-looking design**: only Lucide Icons, no gradients/neon/emoji, WCAG AA, 10 essential UX-psychology principles
- **JSDoc/TSDoc required**, no inline comments inside functions, all explanations in 日本語
- **Git rules**: no `rebase` / `reset --hard` / `push --force`; conflicts resolved via merge commits

## Configuration options

`/my-harness-init` interview produces `<root>/.my-harness/.config`:

```bash
PROJECT_NAME=todo-app
USE_WEB=yes
USE_IOS=no
USE_ANDROID=no
USE_DB=yes
DB_KIND=d1                    # cloudflare d1
USE_EMAIL=yes                 # Resend + password reset
USE_PLAYWRIGHT=yes
USE_MAESTRO=no
USE_CLAUDE_ACTION=yes
CLAUDE_AUTH=oauth             # or "api"
USE_GLOBAL_CLAUDE=yes         # inherit ~/.claude/CLAUDE.md
USE_GITHUB_ISSUES=yes         # or "no" → docs/task/*.md
CODEX_SESSION=my-harness-init
```

You can re-run `bootstrap.sh <root> --config <root>/.my-harness/.config` non-interactively.

## Troubleshooting

- **Skill doesn't fire**: Restart Claude Code or `/clear`
- **Hook doesn't write to talk/**: Check `~/.claude/settings.json` has `UserPromptSubmit` and `Stop` hook entries from the plugin
- **Codex returns auth error**: Run `/harness-check-codex-auth`, then `codex login`
- **Conflict during hotfix back-merge**: Use `/harness-resolve-conflict` (never rebase)
- **`drizzle-kit push` accidentally used**: revert and use `drizzle-kit generate --name <descriptive>` then `wrangler d1 migrations apply`
- **Update plugin**: `/plugin marketplace update` then `/plugin install my-harness@my-harness-generator`

## Contributing

PRs welcome. The plugin enforces its own conventions on its own development:
- All shell scripts must `bash -n` clean
- All SKILL.md require front-matter `name` and `description`
- All commits via Conventional Commits + Japanese body
- See [`docs/WORKFLOW.md`](./docs/WORKFLOW.md) for the full lane-based workflow

## License

MIT (see [LICENSE](./LICENSE))
