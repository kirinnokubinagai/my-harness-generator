---
name: my-harness-adopt
description: Bring the current directory into the harness layout — idempotent. On first run (no .bare/) it converts an existing git repo into .bare/ + main/stage/dev worktrees while preserving commit history. On subsequent runs (.bare/ already present) it refreshes dev/.my-harness/ from the latest plugin assets, regenerates dev/CLAUDE.md and dev/AGENTS.md, and appends any new config flags with safe defaults. .bare/, worktrees, and code are never touched on the refresh path. Fires when the user says "/my-harness-adopt", "既存プロジェクトに導入", "adopt this repo", "harness を最新版に", "plugin update を反映", or similar.
---

# /my-harness-adopt

Single entry point for both initial adoption and subsequent refresh. The skill decides which path to run by checking whether the project root already has `.bare/`.

## Resolve the project root

```bash
ROOT="$(pwd)"
__resolve_project_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}

if [ -d "$ROOT/.bare" ]; then
  # We're inside an adopted project — resolve to project root.
  ROOT="$(__resolve_project_root "$ROOT")"
fi
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
```

## Decide which path to take

```bash
if [ -d "$ROOT/.bare" ]; then
  MODE="refresh"
else
  MODE="initial"
fi
echo "[adopt] mode=$MODE root=$ROOT"
```

## Path 1 — initial adoption (`MODE=initial`)

Used when the directory is a normal git repo (`.git/` present) and is NOT yet in the harness layout. **Destructive but reversible** — `.git/` is moved to a timestamped backup, so a rollback is possible.

### Preconditions

```bash
[ -d "$ROOT/.git" ] || { echo "::error:: $ROOT/.git not found — not a git repo. Use /my-harness-init for an empty directory."; exit 1; }
( cd "$ROOT" && git diff --quiet && git diff --cached --quiet ) || { echo "::error:: working tree dirty. Commit or stash first."; exit 1; }
git -C "$ROOT" rev-parse --verify HEAD >/dev/null 2>&1 || { echo "::error:: HEAD has no commits."; exit 1; }
```

### Step 1 — Collect minimal `.my-harness/.config` via `AskUserQuestion`

| Key | Question | Default |
|---|---|---|
| `PROJECT_NAME` | Project name | basename of `$ROOT` |
| `LANG` | Output language for harness messages | `en` / `ja` (default `en`) |
| `USE_CODEX` | Use Codex CLI for engineer / reviewer / analyst turns | `yes` / `no` (default `yes`) |
| `CODEX_AUTH` | Codex auth method (only if USE_CODEX=yes) | `subscription` / `api-key` (default `subscription`) |
| `USE_CODEX_ANALYST` | analyst delegates to Codex | `yes` / `no` (default `yes`) |
| `USE_CODEX_ENGINEER` | engineer delegates to Codex | `yes` / `no` (default `yes`) |
| `USE_CODEX_REVIEWER` | reviewer delegates to Codex | `yes` / `no` (default `yes`) |
| `USE_CODEX_E2E_REVIEWER` | e2e-reviewer report synthesized by Codex | `yes` / `no` (default `no`) |
| `USE_PLAYWRIGHT` | Run Playwright web E2E | auto-detect from `package.json` if possible |
| `USE_MAESTRO` | Run Maestro mobile E2E | `yes` / `no` (default `no`) |
| `USE_GITHUB_ISSUES` | Source tasks from GitHub Issues vs local `dev/docs/task/child/*.md` | `yes` / `no` (default `no`) |
| `USE_GLOBAL_CLAUDE` | Honour `~/.claude/CLAUDE.md` inside this project | `yes` / `no` (default `yes`) |

Save to `$ROOT/.my-harness/.config` in the same `KEY=value` format `bootstrap.sh` produces. Include `ROOT=$ROOT` and `current_phase=adopted`.

### Step 2 — Run the structure conversion

```bash
bash "$SKILL_DIR/scripts/adopt-existing.sh" "$ROOT" || exit $?
```

After success the layout is `{.bare/, main/, stage/, dev/}` with tracked files moved into `dev/`. The original `.git/` is at `$ROOT/.my-harness-backup/<ts>/git/`.

### Step 3 — Run bootstrap with the saved config

```bash
bash "$SKILL_DIR/scripts/bootstrap.sh" "$ROOT" --config "$ROOT/.my-harness/.config" || exit $?
```

This installs `dev/.my-harness/` (harness body), hooks, and `dev/.claude/settings.json` when `USE_GLOBAL_CLAUDE=no`.

### Step 4 — Hand off

```
Adoption complete (initial).
  Layout:   $ROOT/{.bare, main, stage, dev}
  Backup:   $ROOT/.my-harness-backup/<ts>/git/   (original .git, kept for rollback)

Restart Claude Code from the dev/ worktree:

  exit
  cd $ROOT/dev && claude

Then run /harness-team-lead.
```

## Path 2 — refresh after plugin upgrade (`MODE=refresh`)

Used when `.bare/` already exists. **Non-destructive, idempotent** — re-runs `bootstrap.sh --config` so the plugin's latest assets are rsync-overwritten into `dev/.my-harness/`, `dev/CLAUDE.md` / `dev/AGENTS.md` are regenerated, and any new config flags are appended with safe defaults. `.bare/`, worktrees, code, and existing `.my-harness/.config` keys are untouched.

### Preconditions

```bash
[ -f "$ROOT/.my-harness/.config" ] || { echo "::error:: $ROOT/.my-harness/.config missing. Cannot refresh without an existing config — adopt first (move .bare/ aside if it's broken)."; exit 1; }
```

### Step 1 — Re-run bootstrap

```bash
bash "$SKILL_DIR/scripts/bootstrap.sh" "$ROOT" --config "$ROOT/.my-harness/.config" || exit $?
```

What this does:

- `dev/.my-harness/` rsync-overwritten from the plugin's current contents — newly added files appear, removed ones disappear.
- `dev/CLAUDE.md` and `dev/AGENTS.md` regenerated from `templates/CLAUDE.md.tmpl`.
- `.my-harness/.config` re-written with all current fields. Flags introduced in newer plugin releases get safe defaults (`no` when not previously set).
- `.bare/`, `main/`, `stage/`, `dev/`, and `lanes/feat-*` worktrees are NOT touched. No git operations.

### Step 2 — Hand off

```
Refresh complete.
  Plugin version: <read from $SKILL_DIR/.claude-plugin/plugin.json>
  Project root:   $ROOT
  Refreshed:      dev/.my-harness/, dev/CLAUDE.md, dev/AGENTS.md, .my-harness/.config

If a /harness-team-lead session is currently running, the new rules WILL apply on the next ASSIGNMENT (agents read .my-harness/rules/ at the start of each task). Existing teammate system prompts are NOT re-loaded mid-session — for instruction changes that live in the agent definitions themselves, restart the harness team:

  exit
  rm -rf ~/.claude/teams/harness-team/   # avoid suffixed-name reuse
  cd $ROOT/dev && claude
  /my-harness:harness-team-lead
```

## Rollback (initial path only)

If something goes wrong on the initial path:

```bash
cd "$ROOT"
rm -rf .bare main stage dev .my-harness
mv .my-harness-backup/<ts>/git .git
```

The refresh path has no destructive operation, so rollback is unnecessary.

## Hard rules

- Refuses to convert when working tree is dirty (initial path).
- Never deletes `.my-harness-backup/` automatically.
- Refresh path never touches git state, never removes files outside `dev/.my-harness/`.
- Never runs git commands beyond what `adopt-existing.sh` does on the initial path.
