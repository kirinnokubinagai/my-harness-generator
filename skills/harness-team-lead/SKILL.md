---
name: harness-team-lead
description: 4-lane parallel implementation orchestrator using Claude Code Agent Teams. Creates the `harness-team` once, then adds lanes (4 teammates per lane) one at a time as resources allow, dispatches one issue per lane, and clears the lane between issues. Each lane has analyst-N, engineer-N, e2e-reviewer-N, reviewer-N. Fires when the user says "/harness-team-lead", "start the team", "next batch of issues", or similar. Required after /my-harness-init has finished setup.
---

# /harness-team-lead

The lead orchestrator for parallel issue implementation. The team is `harness-team`. Lanes are 1..4; each lane has four persistent teammates: `analyst-N`, `engineer-N`, `e2e-reviewer-N`, `reviewer-N`. Lanes are added one at a time, only when the host has the resources for another lane. Teammates are persistent within a session — after each issue completes the lane is `/clear`'ed and reused for the next issue, never destroyed and recreated.

## Prerequisite — Agent Teams enabled

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}/skills/harness-team-lead"
bash "$SKILL_DIR/scripts/check-agent-teams-enabled.sh" || exit $?
```

If non-zero, surface the remediation message to the user and stop.

## Precondition — project initialized + resources OK

The user launches Claude Code from `<project>/dev/` (typically `cd <project>/dev && claude`). Pass `$(pwd)` to every script — they normalise to the project root (the directory holding `.bare/`) internally.

```bash
ROOT="$(pwd)"
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}/skills/harness-team-lead"
bash "$SKILL_DIR/scripts/preflight.sh" "$ROOT" || exit $?
```

`preflight.sh` checks: `.my-harness/.config` exists, ≥ 20 GB disk, ≥ 4 GB reclaimable RAM, swap ≤ 1 GB, compressor ≤ 6 GB, no `nix-collect-garbage` running. On any failure the script writes the remediation message to stderr — surface it to the user, do not retry silently.

## Output discipline (non-negotiable)

- **Do not narrate intermediate steps.** No "preflight OK", "ROOT confirmed", "Codex daemon started", "next step", "team created". Run the bash, move on.
- **Do not cat/display script output.** `preflight.sh`, `list-pending-issues.sh`, `check-team-exists.sh`, `spawn-lane-decision.sh` print machine-readable output that the lead consumes internally. The user does not need to see it.
- **The only user-facing output is the final status table** (Step 3f) and any user-actionable error (corrupt team, blocked lane, etc.).
- **Do not run `ls`, `echo $VAR`, or other introspection commands** to "verify" what just happened. Trust the script exit codes.

## Hard prohibitions (non-negotiable)

- **Never call `Agent({name: X})` if `X` is already a member of `harness-team`.** Claude Code's runtime auto-disambiguates name collisions by suffixing (`X-2`, `X-3`, ...), which produces a corrupt team that can no longer be reasoned about. The `spawn-lane-decision.sh` gate (Step 3) is the only authorized source of new-spawn permission — call it before every `Agent({})`. The four lane teammates are spawned ONCE per lane (in 3a) and reused — analyst-N talks to engineer-N / e2e-reviewer-N / reviewer-N via `SendMessage` only.
- **Never spawn a 5th lane.** Lanes are 1..4. Tasks queue when no lane is free.
- **Never invoke `nix-collect-garbage` / `nix-store --gc` from this skill.** Disk-full conditions are reported to the user; the user runs cleanup externally.
- **Never spawn long-running background bash** (`nohup ... &`).
- **Never `TeamDelete` mid-session** to "reset" a corrupt team. Surface the corruption to the user with the recovery instructions.


## Disk-full handling

If any analyst-N reports `[lane=N issue=#X status=blocked-disk-full ...]` (or any teammate sends `ENOSPC`):

1. Mark the lane `paused-disk-full` in dispatch state.
2. Send one message to the user: `Lane N blocked by ENOSPC. Free disk space, then say "resume lane N".`
3. Do not start any cleanup ourselves. Do not retry until the user says `resume lane N`.

## Step 0 — Start the shared Codex daemon

Invoke the `harness-codex-daemon` skill with action `start`. Idempotent: no-op if already running. The daemon is a single Codex `app-server` listening on `ws://127.0.0.1:7373` shared across lanes, so 4 concurrent Codex calls collapse onto one process. If startup fails, lanes fall back to per-call stdio — best-effort, not a precondition.

## Step 1 — List pending tasks

```bash
bash "$SKILL_DIR/scripts/list-pending-issues.sh" "$ROOT" > /tmp/harness-pending.tsv
```

Capture stdout to the file; do NOT cat or display the contents. The lead consumes the rows internally for the dispatch loop. Each teammate runs `build-dev-env.sh "$WORKTREE"` itself when its ASSIGNMENT/TEST/REVIEW arrives — there is no project-root devshell warmup, because the project-root holds only `.bare/` and worktrees, not a `flake.nix`.

Output is tab-separated, four fields per line: `<id>\t<lane>\t<owned_files_csv>\t<title>`.

- `id` — task id (e.g. `0001-07`) or GitHub issue number
- `lane` — preferred lane (1..4) from front matter / `lane-N` GitHub label; empty if unspecified
- `owned_files` — comma-separated paths/globs the task owns
- `title` — short title

Pending = `status: pending` in front matter / `state: open AND label: ready` on GitHub. Tasks with `status: in_progress` (set by analyst-N at Step 0.5 of issue processing) are filtered out — this is what stops `/loop` wakeups from re-dispatching the same task.

## Step 2 — Create or reuse the team

```bash
TEAM_STATE=$(bash "$SKILL_DIR/scripts/check-team-exists.sh")
# stdout: absent | present | corrupt
```

- `absent`  — call `TeamCreate({team_name: "harness-team", description: "4-lane parallel implementation team."})` once. Do NOT create any teammates here; teammates are added per lane in Step 3.
- `present` — go straight to Step 3. Do NOT call `TeamCreate`.
- `corrupt` — stop. The script printed the recovery instructions on stderr (delete `~/.claude/teams/harness-team/` and start a fresh session). Surface that to the user.

Empty teams are valid. The team file exists from `TeamCreate`; its members grow as lanes are added in Step 3.

## Observability — run the watchdog in a separate terminal

For visibility, the user opens a second terminal next to this session and runs:

```bash
bash "$SKILL_DIR/scripts/monitor-agents.sh" "$ROOT"                 # live view
bash "$SKILL_DIR/scripts/monitor-agents.sh" "$ROOT" --watchdog &    # background watchdog
```

The watchdog scans `<root>/.my-harness/logs/agents.log` every 30 s (configurable via `--interval`) and appends classified anomalies as JSONL to `<root>/.my-harness/logs/anomalies.jsonl`. You (the lead) read that file at the top of every Step 3 iteration (see Step 3.0 below). The agents themselves write to `agents.log` via `scripts/agent-log.sh` at every status boundary.

## Step 3 — Parallel dispatch loop

### Step 3.0 — Anomaly check (run BEFORE 3a, every iteration)

```bash
ANOM="$ROOT/.my-harness/logs/anomalies.jsonl"
if [ -f "$ANOM" ]; then
  # Read only new anomalies since the last scan. Persist the byte offset.
  STATE="$ROOT/.my-harness/logs/anomalies.offset"
  OFFSET="$(cat "$STATE" 2>/dev/null || echo 0)"
  NEW="$(tail -c +"$((OFFSET + 1))" "$ANOM" 2>/dev/null)"
  wc -c < "$ANOM" > "$STATE" 2>/dev/null
fi
```

For each new anomaly line `{"ts","kind","agent","detail"}`, decide intervention from this table. Apply it deterministically; do not "interpret" the anomaly with free-form reasoning.

| `kind` | Intervention |
|---|---|
| `stagnation` | `SendMessage({to: agent, content: "STATUS_PING: no event for >10 min. Report current status now."})` once. If the same agent stagnates again within the next 10 min, escalate to user as `Lane <N> <agent> is unresponsive (stagnation x2). Suggest: kill the worktree and re-dispatch.` |
| `repeated-blocked` | The agent has reported the same blocker ≥3 times. Mark the lane `paused-<blocker>`, surface ONE message to the user with the blocker and the recovery steps from the relevant "*-handling" section. Do not auto-retry. |
| `codex-exec-failure` | 3+ consecutive non-zero exits from `codex exec`. SendMessage to the agent: `FALLBACK: switch to claude mode for this issue. The Codex sandbox or auth is unhealthy.` Set `USE_CODEX_<ROLE>=no` ONLY in-memory for this issue (do NOT modify `.config`). After the issue completes, the next assignment restores normal mode. |
| `codex-no-op` | `engineer-N` reported `impl-done changed=0`. SendMessage to engineer: `FIX: codex-exec finished but no files were modified. Re-read the brief and explicitly state which files you will modify before running codex-exec again.` |
| `suffixed-name` | Critical — auto-disambiguation bug. STOP all dispatch immediately. Surface to user: `Suffixed teammate detected (<name>). Delete ~/.claude/teams/harness-team/ and restart Claude Code in dev/.` |

The lead reads anomalies at the top of every 3a / 3c / 3e iteration. The agents continue to make their own decisions; intervention is additive — the lead's intervention messages are received as ordinary inbound `SendMessage` by the affected agent and processed alongside whatever the agent was doing.

In-memory state:
- `pending_queue` — task ids waiting for a lane
- `lane_status` — `{ "lane-1": "absent" | "idle" | { "issue": <id>, "phase": <state> } | "paused-...", ... }` (init: all `"absent"`)
- `completed` — list of `{issue, pr_url, commit_sha}`

**Spawn is sequential, dispatch is parallel.** Lanes are added one at a time (resource check before each), but once spawned they run concurrently. The lead never blocks on a single lane.

### 3a. Fill all available lanes (initial burst)

Repeat until either `pending_queue` is empty OR no more lanes can be assigned:

1. Pick the next dispatchable task: walk `pending_queue` from the front; for each candidate apply preferred-lane and `owned_files` conflict checks (see 3a-rules below). Stop at the first task that fits some target lane.
2. Decide the target lane:
   - If the task's preferred lane is `idle`, target it.
   - If the task's preferred lane is `absent`, target it (it will be spawned).
   - If the preferred lane is busy, defer the task and look at the next candidate.
   - If no preferred lane, prefer the lowest-numbered `idle` lane; fall back to the lowest-numbered `absent` lane.
3. If the target lane is `absent`, run the spawn gate:
   ```bash
   bash "$SKILL_DIR/scripts/spawn-lane-decision.sh" <N> "$ROOT"
   # stdout: DECISION=<SPAWN|SKIP|REFUSE> LANE=<N> NAMES=... REASON=...
   ```
   - `SPAWN` → call `Agent({})` for each name in `NAMES`, **one at a time**, waiting for each `[<name> status=ready]` ack before the next. When all four have acked, set `lane_status["lane-N"] = "idle"`.
     ```
     Agent({
       team_name: "harness-team",
       name: "analyst-N",        // or engineer-N / e2e-reviewer-N / reviewer-N
       subagent_type: "harness-analyst",   // or harness-engineer / harness-e2e-reviewer / harness-reviewer
       prompt: "You are analyst-N of lane-N. Acknowledge with [analyst-N status=ready] and idle. Do not Read, run Bash, or call any tool until you receive an ASSIGNMENT message."
     })
     ```
   - `SKIP` → the four teammates are already in the team config (e.g. after `/loop` re-entry). Set `lane_status["lane-N"] = "idle"`. Do NOT call `Agent({})` (would trigger the suffix bug).
   - `REFUSE` (resource pressure) → stop the burst loop. The lanes already running stay running; pending tasks wait. Surface the REASON to the user (one short line).
   - `REFUSE` (corruption / `partial-lane` / `corrupt-team`) → stop entirely and surface the recovery instructions.
4. Create the lane worktree, then send the ASSIGNMENT (do not wait for completion; immediately loop back to step 1 to fill the next lane):
   ```bash
   bash "$SKILL_DIR/scripts/harness-worktree.sh" add "$ROOT" "<id>" "<slug>"
   ```
   ```
   SendMessage({
     to: "analyst-N",
     type: "message",
     content: "ASSIGNMENT
       root: <ROOT>
       issue: #<X>
       branch: feat/<X>-<slug>
       worktree: <ROOT>/lanes/feat-<X>-<slug>/
       owned_files: [<list>]
       language: <LANG>
       Begin Step 1 (brief production), then dispatch engineer-N → e2e-reviewer-N → reviewer-N. After all gates pass, run git commit + push + gh pr create yourself. Final completion message to me: [analyst-N issue=#<X> status=pr-created pr=<URL>]."
   })
   ```
   Set `lane_status["lane-N"] = { issue: X, phase: "1-brief" }`. **Loop back to step 1 immediately** — do not wait for the analyst.

The burst exits when `pending_queue` is empty OR every active lane is busy AND `spawn-lane-decision.sh` last returned `REFUSE` for the next absent lane (resource pressure).

### 3a-rules (preferred-lane and owned_files)

- **Preferred lane**: if a task has a `lane` field, that's the lane it was authored for (its `owned_files` were chosen with that lane in mind). Defer the task rather than send it to a different lane.
- **owned_files conflict**: if any currently-active lane is processing a task whose `owned_files` overlap (path-glob match) with the candidate's `owned_files`, defer the candidate.
- **`owned_files` is a dispatch-time gate only.** Once a task is in flight inside a lane's worktree, engineer-N may touch any file the brief requires, including shared config (`biome.json`, `package.json`, etc.). Do not police the running lane's file changes against `owned_files`; that is not what the field is for.

### 3b. Wait for any completion

When the burst exits with at least one lane busy, wait for inbound `SendMessage` from any analyst-N. The Agent Teams runtime delivers it to the lead. Possible messages:

```
[analyst-N issue=#X step=<step> status=<state>]
[analyst-N issue=#X status=pr-created pr=https://...]
[lane=N issue=#X status=blocked-codex-auth role=<engineer|e2e|reviewer> rescue=<path>]
[lane=N issue=#X status=blocked-disk-full]
[lane=N issue=#X status=blocked-workspace-not-ready details=<line>]
```

On `pr-created`: proceed to 3c for that lane.
On `blocked-codex-auth`: see "Codex auth handling".
On `blocked-disk-full`: see top of file.
On `blocked-workspace-not-ready`: mark this lane `paused-workspace`. Surface ONE message to the user: `Lane N (issue #X) needs an earlier monorepo-setup task to land first. Once that PR is merged into dev, say "resume lane N".` Do NOT auto-retry. Do NOT dispatch another task to this lane until resumed. Other lanes keep running.
On any intermediate `step=<step> status=<state>`: just update bookkeeping; do not interrupt other lanes.

### 3c. Clear the finishing lane and refill it

When analyst-N reports `status=pr-created`:

1. Send `/clear` to all four teammates of that lane in one message (four parallel `SendMessage` calls):
   ```
   SendMessage({ to: "analyst-N",      content: "DIRECTIVE: clear_context\nInvoke /clear in your own session, then ack [analyst-N status=cleared ready-for-issue]." })
   SendMessage({ to: "engineer-N",     content: "DIRECTIVE: clear_context\nInvoke /clear, then ack [engineer-N status=cleared ready]." })
   SendMessage({ to: "e2e-reviewer-N", content: "DIRECTIVE: clear_context\nInvoke /clear, then ack [e2e-reviewer-N status=cleared ready]." })
   SendMessage({ to: "reviewer-N",     content: "DIRECTIVE: clear_context\nInvoke /clear, then ack [reviewer-N status=cleared ready]." })
   ```
2. Wait for all four `cleared` acks (other lanes keep working in the background).
3. Remove the lane worktree:
   ```bash
   bash "$SKILL_DIR/scripts/harness-worktree.sh" remove "$ROOT" "<id>" "<slug>"
   ```
4. Set `lane_status["lane-N"] = "idle"`.
5. **Try to refill this lane immediately** by re-running step 3a's pick-and-dispatch logic. This way a finished lane is back to work as soon as its `/clear` completes, without waiting for other lanes.
6. Return to 3b (wait for the next completion).

### 3d. Loop exit

When `pending_queue` is empty AND every lane is `"idle"` or `"absent"`, the batch is done. Print a status table to the user (lane / last issue / PR URL / status), then ask via `AskUserQuestion`: continue with another batch, or shut down.

## Step 4 — Shutdown

When the user agrees to stop or no more pending tasks remain, send `shutdown_request` to every teammate currently in the team (single message, parallel calls), wait for `shutdown_response` from each, then:

```
TeamDelete({ team_name: "harness-team" })
```

Stop the shared Codex daemon by invoking the `harness-codex-daemon` skill with action `stop` (best-effort).

Print a final summary to the user.

## Codex auth failure handling

When a lane reports `[lane=N issue=#X status=blocked-codex-auth role=<engineer|e2e|reviewer> rescue=<path>]`:

1. Mark the lane `paused-codex-auth` (do NOT mark idle — work is unfinished).
2. Read `<rescue>`:
   ```bash
   RESCUE_SESSION_ID=$(jq -r '.session_id' "<rescue>")
   RESCUE_REASON=$(jq -r '.reason' "<rescue>")
   ```
3. Tell the user:
   ```
   Lane N (issue #X, role=<role>) is paused — Codex auth issue (<RESCUE_REASON>).
   Action required:
     - login-expired / preflight-not-logged-in: run `codex login`, then say "resume lane N"
     - subscription-or-quota: renew or set USE_CODEX_<ROLE>=no in .my-harness/.config, then say "resume lane N"
   ```
4. On `"resume lane N"`:
   - Run `bash scripts/check-codex-auth.sh` to confirm logged in.
   - SendMessage to analyst-N: `RESUME\nROLE=<role>\nINHERITED_SESSION_ID=<RESCUE_SESSION_ID>` so analyst-N can forward the resume to the affected teammate.

## Stateless across `/clear` of the lead session

When the lead session itself becomes too heavy, write the dispatch state to `<ROOT>/.my-harness/team-state.json`:

```json
{
  "team_name": "harness-team",
  "lane_status": {
    "lane-1": "idle",
    "lane-2": { "issue": 47, "phase": "engineer" },
    "lane-3": "absent",
    "lane-4": "paused-codex-auth"
  },
  "pending_queue": [50, 51, 52],
  "completed": [{"issue": 41, "pr": "https://..."}]
}
```

Tell the user to `/clear` the lead and re-invoke `/harness-team-lead`. On re-invocation, `check-team-exists.sh` returns `present` and the dispatch loop reads `team-state.json` to resume. Do NOT re-create the team. `spawn-lane-decision.sh` will return `SKIP` for any lane whose four teammates are still members.

## Hard rules (recap)

- Exactly 4 lanes maximum. Tasks queue when all four are busy.
- Teammates are persistent within a session. `/clear` between issues; never destroy and recreate mid-session (except Step 4 shutdown).
- One issue per lane at a time. Never assign a second issue to a lane until it has reported `pr-created` AND all four teammates have acked `cleared`.
- The lead only talks to analyst-N during processing. analyst-N dispatches the rest of its lane internally. The two exceptions are Step 3e (the post-issue clear sweep) and Step 4 (shutdown).
- No nested teammates. No teammate creates another teammate.
- Every `Agent({})` call is preceded by a `spawn-lane-decision.sh` `SPAWN` decision. No exceptions.

## Output format (status report to user)

```
[team-lead summary]
team: harness-team (lanes spawned: 2 of 4)
lanes:
  lane-1  idle              last: #41 → https://github.com/.../pull/12
  lane-2  in-progress #47   active=engineer-2
  lane-3  absent            (not yet spawned — waiting for resources or queue)
  lane-4  absent
queue:    [#50, #51, #52]
next: dispatching #50 → lane-1
```
