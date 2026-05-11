---
name: my-harness-update
description: Refresh an already-adopted harness project with the latest plugin version. Re-runs bootstrap.sh against the existing .my-harness/.config so dev/.my-harness/ gets the latest rules / scripts / agent-log / monitor / codex-exec, dev/CLAUDE.md and dev/AGENTS.md are re-generated, and any new config flags (e.g. USE_CODEX_ANALYST in 4.0.0) are appended with safe defaults. Existing .bare/, main/stage/dev/lanes worktrees, commit history, and code under each worktree are NOT touched. Fires when the user says "/my-harness-update", "harness を最新版に", "plugin update を反映", "refresh harness", "再 adopt したい", or similar.
---

# /my-harness-update

Re-deploys the latest plugin assets into an already-adopted harness project. Use this after `/plugin marketplace update && /plugin install my-harness@my-harness-generator` to push the new rules / scripts / templates into your project's `dev/.my-harness/`.

This is the safe counterpart to `/my-harness-adopt`: adopt is one-shot and refuses to run twice; update is idempotent and can be run any number of times.

## Preconditions

```bash
ROOT="$(pwd)"
# Resolve to project root if cwd is dev/ or a lane worktree.
__resolve_project_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo ""
}
ROOT="$(__resolve_project_root "$ROOT")"

[ -n "$ROOT" ] && [ -d "$ROOT/.bare" ] || { echo "::error:: not inside a harness-adopted project (no .bare/ found walking up). Use /my-harness-adopt first."; exit 1; }
[ -f "$ROOT/.my-harness/.config" ] || { echo "::error:: $ROOT/.my-harness/.config missing. Cannot update without an existing config — use /my-harness-init or /my-harness-adopt instead."; exit 1; }
```

If either check fails, surface the message to the user and stop.

## Step 1 — Re-run bootstrap with the existing config

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
bash "$SKILL_DIR/scripts/bootstrap.sh" "$ROOT" --config "$ROOT/.my-harness/.config" || exit $?
```

What this does:

- **`dev/.my-harness/` is rsync-overwritten** from the plugin's current contents (rules/, scripts/, agents/, templates/, hooks/, etc.). Any files only present in the plugin (newly added in the latest release) appear; any files removed in the plugin disappear.
- **`dev/CLAUDE.md` and `dev/AGENTS.md` are re-generated** from `templates/CLAUDE.md.tmpl` so they pick up the latest rule pointers.
- **`.my-harness/.config` is rewritten** with all current fields. New flags introduced in the latest release (e.g. `USE_CODEX_ANALYST` in 4.0.0) are appended with safe defaults (`no` when not previously set).
- **`.bare/`, `main/`, `stage/`, `dev/` worktrees, and any `lanes/feat-*` worktrees are NOT touched.** No git operations, no destructive changes to your code.

## Step 2 — Print a short summary

After bootstrap returns 0, print exactly:

```
Update complete.
  Plugin version: <read from $SKILL_DIR/.claude-plugin/plugin.json>
  Project root:   $ROOT
  Refreshed:      dev/.my-harness/, dev/CLAUDE.md, dev/AGENTS.md, .my-harness/.config

If you adjusted Codex flags (USE_CODEX_ANALYST, USE_CODEX_ENGINEER, etc.) interactively, the new values are now in $ROOT/.my-harness/.config and $ROOT/dev/.my-harness/.config.

If a /harness-team-lead session is currently running, the new rules WILL apply on the next ASSIGNMENT (agents read .my-harness/rules/ at the start of each task). Existing teammate system prompts are NOT re-loaded mid-session — for instruction changes that live in the agent definitions themselves, restart the harness team:

  exit                                          # close current Claude Code
  rm -rf ~/.claude/teams/harness-team/          # avoid suffixed-name reuse
  cd $ROOT/dev && claude
  /my-harness:harness-team-lead
```

## Hard rules

- This skill never touches `.bare/`, `main/`, `stage/`, `dev/` worktrees' git state, or `lanes/feat-*` worktrees.
- Never removes `.my-harness-backup/` directories from previous adopt runs.
- If the user wants to genuinely re-adopt (e.g. after corrupting `.bare/`), they must move the broken layout aside manually and run `/my-harness-adopt`. This skill refuses to delete things on their behalf.
- Never runs git commands. Update is purely a file-distribution operation.
