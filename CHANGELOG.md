# Changelog

All notable changes to this plugin documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

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
- 5 agents (for 4-lane parallel development): `harness-team-lead`, `harness-analyst`, `harness-engineer`,
  `harness-e2e-reviewer`, `harness-reviewer`
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
