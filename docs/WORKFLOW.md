# Harness Workflow

## Roles and Parallel Lanes

team-lead (you) receives GitHub issues and assigns them across 4 lanes. Each lane processes in the order:
analyst-N → engineer-N → e2e-reviewer-N → reviewer-N.

| Role | Primary Responsibility |
|------|------------------------|
| team-lead | Issue assignment, progress aggregation, final approval |
| analyst-N | Investigation, requirements clarification, conflict checks, progress reporting |
| engineer-N | Implementation (code / infrastructure / design mocks) |
| e2e-reviewer-N | E2E impact assessment + Playwright/Maestro execution |
| reviewer-N | Code quality review for engineer convention compliance |

## Standard Flow (per issue)

1. team-lead assigns a GitHub child issue to analyst-N.
2. analyst-N investigates, finalizes acceptance criteria → requests implementation from engineer-N → reports to team-lead.
3. engineer-N implements in a feature worktree (`/lanes/feat-<issue>/`), reports completion to analyst-N.
4. analyst-N assesses E2E impact:
   - Impact detected → e2e-reviewer-N runs Playwright/Maestro
   - Failure → request fix from engineer-N (via analyst-N) → report to team-lead
   - No impact, or passed → proceed to reviewer-N
5. reviewer-N checks convention compliance (naming / JSDoc / Hono Clean Arch / Nix pure, etc.).
   - Violations found → request fix from engineer-N (via analyst-N) → report to team-lead
6. After all checks pass, husky runs pre-commit/pre-push (format/lint/test), pushes, and creates a PR targeting dev.
7. analyst-N sends final report to team-lead. team-lead aggregates results and moves to the next child issue.

## Branch and Merge Rules

| from → to | Allowed when |
|-----------|--------------|
| feat/* → dev | PR + format/lint/test/typecheck pass |
| dev → stage | **Human (you) approval** + OWASP ZAP + Playwright + Maestro + Semgrep + Trivy pass |
| stage → main | **Human (you) approval** + all gates green |
| hotfix/* → main | Emergency approval + minimum test/lint/format (see HOTFIX.md) |

## Conflict Policy

- analyst-N checks for conflict potential every time a progress report is received, using commands such as `git fetch origin dev && git merge-base --is-ancestor origin/dev HEAD`.
- If a conflict occurs, engineer-N is asked to resolve it **with a merge commit**.
- **`git reset` / `git rebase` / `git push --force` are prohibited.**

## Initial Setup and the dev / stage / main Relationship

Immediately after introducing the harness, all 3 branches share the same "empty initial commit."
**Direct edits to stage / main are prohibited** (Rule 4), so
**bootstrapping husky / biome / nix flake / GitHub Actions must go through the normal flow too.**

Concrete steps:

1. Create a `feat/bootstrap-harness` worktree from dev (`git --git-dir=.bare worktree add -b feat/bootstrap-harness lanes/feat-bootstrap-harness origin/dev`).
2. In that worktree, introduce husky / biome / nix flake / .github / .harness and create a PR targeting dev.
3. Once CI is green and merged to dev → propagate to stage / main via **normal release PRs**:
   - dev → stage (OWASP ZAP / E2E required)
   - stage → main (human final approval + canary)
4. The stage / main worktrees are kept **as merge targets (read-only)**.
   Developers work exclusively on dev and its feat branches.

Exception:
- Only for hotfixes is a worktree created from main (see `HOTFIX.md`).

## Progress Report Format

```
[lane=N issue=#123 phase=engineer→analyst]
status: done|in-progress|blocked
summary: 1-2 lines
artifacts: <PR/commit/file list>
next: next action
risks: conflict probability / impact scope
```
