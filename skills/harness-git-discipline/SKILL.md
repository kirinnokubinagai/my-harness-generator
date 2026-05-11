---
name: harness-git-discipline
description: Absolutely prohibits git rebase / reset --hard / push --force. Conflicts must be resolved with merge commits. Never work directly on the protected branches dev / stage / main. Fires when the user mentions "git conflict", "git reset", "rebase", "force push", or similar.
---

# harness-git-discipline

The discipline that governs every Git operation in the harness.

## Non-negotiable rules

| Operation | Status |
|-----------|--------|
| `git rebase` | **Prohibited** (including interactive) |
| `git rebase --autosquash` | **Prohibited** |
| `git reset --hard` | **Prohibited** |
| `git push --force` | **Prohibited** |
| `git push --force-with-lease` | **Prohibited** (still a form of force push) |
| `git filter-branch` / `filter-repo` | **Prohibited** (post-leak secret removal requires separate approval) |
| **Conflict resolution** | **Always create a merge commit with `git merge --no-ff`** |

## Branch conventions

| Branch | Purpose | Direct push |
|--------|---------|-------------|
| `main` | Production. Merges from stage only | **Prohibited** |
| `stage` | Staging. Merges from dev only | **Prohibited** |
| `dev` | Default integration target. PR destination for feat branches | Normally prohibited (via PR) |
| `feat/<issue>-<slug>` | Feature development, branched from dev | OK |
| `hotfix/<issue>-<slug>` | Emergency fixes, branched from main | OK |

The pre-push hook blocks direct pushes to main / stage.

## Conflict resolution (merge commits only)

```bash
# Inside the feature worktree
cd lanes/feat-123-foo
git fetch origin dev
git merge --no-ff origin/dev -m "merge: resolve with dev (no rebase)"
# Resolve conflicts (preserve the intent of both sides)
nix develop --command pnpm exec biome check .
nix develop --command pnpm exec vitest run
git add -A
git commit  # Merge commit complete
git push origin feat/123-foo  # No --force variants ever
```

## Back-merge after hotfix (main → stage → dev)

All back-merges use `git merge --no-ff`:
```bash
git checkout stage
git merge --no-ff origin/main -m "merge: hotfix back-merge main → stage"
git push origin stage

git checkout dev
git merge --no-ff origin/stage -m "merge: hotfix back-merge stage → dev"
git push origin dev
```

## Why rebase / reset is prohibited

- History rewriting destroys other contributors' work
- Merge commits are an audit trail — "who merged what and when"
- Consistent rules for back-merges
- Guarantees history integrity with 4 parallel development lanes

## Commit message convention (Conventional Commits)

```
<type>(<scope>): <subject in Japanese>

<body in Japanese>
```

Types:
- `feat` / `fix` / `hotfix` / `docs` / `style` / `refactor` / `perf` / `test` / `build` / `ci` / `chore` / `revert`

Example:
```
feat(auth): メールアドレスでのログイン機能を追加

bcrypt cost 12 でハッシュ化、JWT は 15 分の短命トークン。
リフレッシュトークンは 7 日。
```

(Note: commit subjects and bodies are written in Japanese — this is the generated project's default output language convention.)

## If sensitive information appears in history

This is an emergency.
1. Rotate the exposed secret immediately (Resend / Cloudflare / GitHub, etc.)
2. Whether to scrub it from history is a separate decision (requires approval since force-push is needed)
3. Prevention is the priority — gitleaks scheduled scans catch this proactively

## Checklist

- [ ] `git rebase` was not run
- [ ] `git reset --hard` was not run
- [ ] `git push --force` / `--force-with-lease` was not run
- [ ] Conflicts resolved via merge commit
- [ ] No direct push to main / stage
- [ ] Commit message follows Conventional Commits with Japanese body
