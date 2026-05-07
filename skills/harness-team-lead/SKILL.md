---
name: harness-team-lead
description: Coordinator for ongoing 4-lane parallel implementation in an existing harnessed project. Reads .my-harness/.config and the project's issue/task list, partitions issues across up to 4 worktree lanes so they don't conflict, and spawns analyst → engineer → e2e-reviewer → reviewer subagents per lane via Task(subagent_type=...). Fires when the user says "/harness-team-lead", "start the team", "next batch of issues", or similar. Required to invoke after /my-harness-init has finished setup.
---

# /harness-team-lead

This is the **only ongoing-development entry point** users invoke after `/my-harness-init` completes. All 4-lane parallel implementation work starts here.

## Precondition check

```bash
ROOT="$(pwd)"
if [ ! -f "$ROOT/.my-harness/.config" ]; then
  echo "Error: .my-harness/.config not found. Run /my-harness-init first."
  exit 1
fi
source "$ROOT/.my-harness/.config"
```

If `.config` is missing, stop and tell the user: "Run `/my-harness-init` first."

## Step 1: Determine issue source

```bash
USE_GITHUB_ISSUES=$(grep -E "^USE_GITHUB_ISSUES=" "$ROOT/.my-harness/.config" | cut -d= -f2)
```

- `USE_GITHUB_ISSUES=yes` → fetch from GitHub:
  ```bash
  gh issue list --label ready --json number,title,body --limit 20
  ```
- `USE_GITHUB_ISSUES=no` → read from local task files:
  ```bash
  find "$ROOT/dev/docs/task/child" -name "*.md" | xargs grep -l "status: pending" | head -8
  ```

Select up to 8 candidate issues (2 per lane maximum).

## Step 2: Partition issues across lanes (conflict-free)

Do **not** try to predict file lists statically. Instead:

1. Spawn one analyst per candidate issue **in parallel** (all at once):
   ```
   Task(subagent_type=harness-analyst,
        prompt="Declare the files you expect to touch for issue #<N>. Output only a JSON list of file paths. No implementation yet. Worktree: $ROOT. Skills to load: harness-tdd, harness-mask, harness-git-discipline, harness-no-hardcoded-secrets")
   ```
2. Collect the declared file sets.
3. Greedy partition: assign issues to `lane/1` through `lane/4` such that no two issues in the same lane share a file path. If an issue conflicts with all 4 lanes, defer it to the next batch.
4. If mid-run a conflict is detected (analyst reports an unexpected file overlap), re-partition the affected lane by swapping the conflicting issue to the next available lane or the deferred queue.

Maximum 4 lanes active simultaneously.

## Step 3: Spawn the full pipeline per lane

For each lane N with assigned issue #X:

```
Task(subagent_type=harness-analyst,
     prompt="lane=N issue=#X worktree=$ROOT/lanes/feat-<issue#>-<slug>/
Branch: feat/<issue#>-<slug>

Produce the implementation brief, then run the full analyst pipeline:
  analyst → engineer → e2e-reviewer → reviewer → git commit + PR

Skills to load for this lane:
  harness-analyst default: harness-tdd, harness-mask, harness-git-discipline, harness-no-hardcoded-secrets
  Pass to engineer spawn: harness-tdd, harness-jsdoc, harness-hono-clean-arch, harness-drizzle-rules, harness-design-rules, harness-nix-pure, harness-no-hardcoded-secrets, harness-mask
  Pass to e2e-reviewer spawn: harness-nix-pure, harness-mask
  Pass to reviewer spawn: harness-jsdoc, harness-tdd, harness-hono-clean-arch, harness-drizzle-rules, harness-design-rules, harness-no-hardcoded-secrets, harness-git-discipline")
```

**Never use `SendMessage` continuation.** Every subagent is spawned fresh via `Task(subagent_type=...)`.

## Step 4: Monitor and aggregate

Wait for all lane analysts to report back. Collect status messages:
```
[lane=N issue=#X phase=analyst→team-lead status=pr-created pr=<URL>]
```

Present a consolidated status table to the user when all lanes finish:

```
Lane | Issue | Status      | PR
-----|-------|-------------|----
  1  |  #42  | pr-created  | https://github.com/.../pull/17
  2  |  #43  | pr-created  | https://github.com/.../pull/18
  3  |  #44  | blocked     | conflict — deferred to next batch
  4  |  #45  | pr-created  | https://github.com/.../pull/19
```

Ask the user: "Ready to run the next batch? (y/n)"

## Codex auth failure handling

If any subagent returns `blocked-codex-auth`:

1. Pause that lane.
2. Surface the rescue file path from the status message.
3. Tell the user:
   ```
   Lane N (issue #X) is paused — Codex auth expired.
   Run: codex login
   Then reply: resume lane N
   ```
4. On "resume lane N": re-spawn only that lane's analyst with the same issue and worktree, using `Task(subagent_type=harness-analyst, ...)`. The Codex session is preserved server-side.

## Stateless design

team-lead is stateless. On each invocation it re-derives everything from:
- `.my-harness/.config`
- GitHub Issues (or `dev/docs/task/child/*.md`)
- `git worktree list`

There is no `init-state.json` or `team-state.json` continuation path here. If the session becomes heavy (after 10+ issues), tell the user to `/clear` and re-invoke `/harness-team-lead` — it will pick up from the current state of issues and worktrees automatically.
