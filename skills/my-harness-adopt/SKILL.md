---
name: my-harness-adopt
description: Adopt an existing git repository into the harness layout (.bare/ + main/stage/dev/ worktrees + dev/.my-harness/). Preserves the existing commit history. Run from inside the existing repo. Fires when the user says "/my-harness-adopt", "既存プロジェクトに導入", "adopt this repo", or similar.
---

# /my-harness-adopt

Convert an existing git repository in place into the harness layout. The original `.git/` is converted to `.bare/`, every tracked entry is moved into `dev/`, and `main/` `stage/` worktrees are created from the same HEAD. **Commit history is preserved.** A copy of the original `.git/` is left at `<root>/.my-harness-backup/<timestamp>/git/` for rollback.

## Preconditions

```bash
ROOT="$(pwd)"
[ -d "$ROOT/.git" ] || { echo "Not a git repo. cd into the project root first." >&2; exit 1; }
[ -d "$ROOT/.bare" ] && { echo "Already adopted (.bare/ exists)." >&2; exit 1; }
( cd "$ROOT" && git diff --quiet && git diff --cached --quiet ) || { echo "Working tree dirty. Commit or stash first." >&2; exit 1; }
git -C "$ROOT" rev-parse --verify HEAD >/dev/null 2>&1 || { echo "HEAD has no commits." >&2; exit 1; }
```

If any check fails, surface the message to the user and stop.

## Step 1 — Collect minimal `.my-harness/.config`

Use `AskUserQuestion` to ask only the values bootstrap needs. Defaults are conservative; users can edit the file later.

| Key | Question | Choices / default |
|---|---|---|
| `PROJECT_NAME` | Project name | default = basename of `$ROOT` |
| `LANG` | Output language for harness messages | `en` / `ja` (default `en`) |
| `USE_CODEX` | Use Codex CLI for engineer/reviewer turns | `yes` / `no` (default `yes`) |
| `CODEX_AUTH` | Codex auth method (only if USE_CODEX=yes) | `subscription` / `api-key` (default `subscription`) |
| `USE_CODEX_ENGINEER` | engineer-N delegates to Codex | `yes` / `no` (default `yes`) |
| `USE_CODEX_REVIEWER` | reviewer-N delegates to Codex | `yes` / `no` (default `yes`) |
| `USE_CODEX_E2E_REVIEWER` | e2e-reviewer-N synthesizes reports via Codex | `yes` / `no` (default `no`) |
| `USE_PLAYWRIGHT` | Run Playwright web E2E | `yes` / `no` (auto-detect from `package.json` if possible) |
| `USE_MAESTRO` | Run Maestro mobile E2E | `yes` / `no` (default `no`) |
| `USE_GITHUB_ISSUES` | Source tasks from GitHub Issues vs local `dev/docs/task/child/*.md` | `yes` / `no` (default `no`) |
| `USE_GLOBAL_CLAUDE` | Honour `~/.claude/CLAUDE.md` inside this project | `yes` / `no` (default `yes`) |

Write to `$ROOT/.my-harness/.config` in the same `KEY=value` format as `bootstrap.sh` produces. Include `ROOT=$ROOT` and `current_phase=adopted`. Existing fields the user did not pick can be left empty — bootstrap fills sensible defaults.

## Step 2 — Run the structure conversion

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
bash "$SKILL_DIR/scripts/adopt-existing.sh" "$ROOT" || exit $?
```

After success the layout is `{.bare/, main/, stage/, dev/}` and the original tracked files are inside `dev/`. The original `.git/` is at `$ROOT/.my-harness-backup/<ts>/git/`.

## Step 3 — Run bootstrap with the saved config

```bash
bash "$SKILL_DIR/scripts/bootstrap.sh" "$ROOT" --config "$ROOT/.my-harness/.config" || exit $?
```

This installs `dev/.my-harness/` (harness body), hooks, and `dev/.claude/settings.json` if `USE_GLOBAL_CLAUDE=no`.

## Step 4 — Hand off to the user

Print exactly:

```
Adoption complete.
  Layout:   $ROOT/{.bare, main, stage, dev}
  Backup:   $ROOT/.my-harness-backup/<ts>/git/   (original .git, kept for rollback)

Restart Claude Code from the dev/ worktree to start using the harness:

  exit
  cd $ROOT/dev && claude

Then run /harness-team-lead.
```

## Rollback (if anything goes wrong)

If the user wants to undo:

```bash
cd "$ROOT"
rm -rf .bare main stage dev .my-harness
mv .my-harness-backup/<ts>/git .git
# Anything dev/ created (commits, hooks files) should be inspected manually.
```

## Hard rules

- Only run from a directory that already has `.git/` and a clean working tree.
- Do NOT run inside an already-adopted repo (`.bare/` present).
- Never delete `.my-harness-backup/` automatically. The user removes it once they confirm adoption is good.
- This skill never pushes, never creates remotes, never opens PRs. It only touches local file layout.
