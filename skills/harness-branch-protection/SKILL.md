---
name: harness-branch-protection
description: Applies harness-standard branch protection to main / stage / dev in one shot via `setup-branch-protection.sh`. Enforces force-push prohibition, required reviews, required status checks, auto-merge enablement, and merge-commit preservation. Fires when the user mentions "branch protection", "disable force push", "require PR", or similar.
---

# harness-branch-protection

Applies harness-standard branch protection to all three long-lived branches via the `gh` CLI. Run this **once**, after the repository has been created and pushed.

## Prerequisites

- `gh auth status` passes
- Remote origin has been pushed (main / stage / dev remote refs exist)

## Invocation

```bash
cd <root>
bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
```

## Protection rules applied (all branches)

- `allow_force_pushes=false` (**force-push disabled**)
- `allow_deletions=false` (branch deletion disabled)
- `required_pull_request_reviews` required (main = 2 reviewers / stage = 1 / dev = 1)
- `dismiss_stale_reviews=true` (new commits invalidate existing approvals)
- `require_code_owner_reviews=true`
- `required_conversation_resolution=true`
- Required status checks: `quality`, `e2e`, `security`, `claude-review`

## Repository settings

- `allow_auto_merge=true` (auto-merge feature enabled)
- `allow_merge_commit=true` (merge commits preserved)
- `allow_squash_merge=false` (squash disabled — rewrites history)
- `allow_rebase_merge=false` (rebase disabled — follows the git policy in `rules/` and `docs/HOTFIX.md`)
- `delete_branch_on_merge=true` (cleanup after merge)

## Verification

```bash
gh api "repos/<owner>/<repo>/branches/main/protection" | jq .
```

## Why this matters

The local git policy (documented in `rules/` and `docs/HOTFIX.md`) prohibits rebase / reset / force-push. This skill enforces the same rules **server-side**, so that even a local `--no-verify` bypass cannot slip through on push. It is the last line of defense.

## Related

- Git discipline: see `rules/` and `docs/HOTFIX.md`
- Secrets setup: `harness-setup-secrets`
- Execution order: bootstrap → branch protection → secrets (once each)
