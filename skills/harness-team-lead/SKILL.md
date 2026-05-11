---
name: harness-team-lead
description: 4-lane parallel implementation orchestrator using Claude Code Agent Teams. Creates the `harness-team` once, then adds lanes (4 teammates per lane) one at a time as resources allow, dispatches one issue per lane, and clears the lane between issues. Each lane has analyst-N, engineer-N, e2e-reviewer-N, reviewer-N. Fires when the user says "/harness-team-lead", "start the team", "next batch of issues", or similar. Required after /my-harness-init has finished setup.
---

# /harness-team-lead

Lead orchestrator. Team `harness-team`. Lanes 1..4, each with 4 persistent teammates (`analyst-N` / `engineer-N` / `e2e-reviewer-N` / `reviewer-N`). Spawn one lane at a time gated by resources; dispatch in parallel; `/clear` and reuse between issues.

## Output discipline

- **No narration**, no progress chatter ("preflight OK", "ROOT confirmed", "team created", "next step"). Run the bash, move on.
- **No `cat`** of script output. preflight / list-pending / check-team-exists / spawn-lane-decision print machine-readable text the lead consumes silently.
- User sees only the final status table (Step 3d) and user-actionable errors.
- No `ls` / `echo $VAR` "verify" commands. Trust script exit codes.

## Hard prohibitions

- **Never `Agent({name: X})` if `X` is already a `harness-team` member.** Claude Code auto-suffixes name collisions to `X-2` etc., corrupting the team. `spawn-lane-decision.sh` is the only authorized source of new-spawn permission. Each lane's four teammates are spawned ONCE and reused; analyst-N talks to the others via `SendMessage` only.
- **Never spawn lane-5+.** Tasks queue.
- **Never invoke `nix-collect-garbage`** from this skill. Disk-full → report to user, they clean up externally.
- **No background bash** (`nohup ... &`).
- **No mid-session `TeamDelete`** to "reset" a corrupt team. Surface to user with recovery steps.

## Disk-full handling

On `[lane=N issue=#X status=blocked-disk-full ...]` (or any `ENOSPC`): mark lane `paused-disk-full`, tell user once `Lane N blocked by ENOSPC. Free disk space, then say "resume lane N".`, then wait. No auto-retry.

## Prerequisite — Agent Teams enabled

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:?}/skills/harness-team-lead"
bash "$SKILL_DIR/scripts/check-agent-teams-enabled.sh" || exit $?
```

If non-zero, surface remediation and stop.

## Precondition — project initialized + resources OK

User launches Claude Code from `<project>/dev/` (`cd <project>/dev && claude`). All scripts resolve `ROOT` to the project root (the dir with `.bare/`) internally.

```bash
ROOT="$(pwd)"
bash "$SKILL_DIR/scripts/preflight.sh" "$ROOT" || exit $?
# Production-grade diagnostics (Codex auth, MAX_LANES vs RAM, daemon liveness,
# Agent Teams env, lane-gate dry run). FAIL → stop and surface remediation.
bash "$CLAUDE_PLUGIN_ROOT/scripts/doctor.sh" || true   # advisory; WARN allowed
```

Checks: `.my-harness/.config` exists, ≥ 20 GB disk, ≥ 4 GB reclaimable RAM, swap ≤ 1 GB, compressor ≤ 6 GB, no `nix-collect-garbage` running. Failure → surface remediation, do not retry silently. `doctor.sh` produces non-blocking WARN for cases like a stale Codex daemon pid — the lead reads those and tells the user before starting Step 0.

## Observability — separate terminal

User opens a second terminal:

```bash
bash "$SKILL_DIR/scripts/monitor-agents.sh" "$ROOT"               # live view
bash "$SKILL_DIR/scripts/monitor-agents.sh" "$ROOT" --watchdog &  # classifies anomalies
```

Watchdog appends classified anomalies to `<root>/.my-harness/logs/anomalies.jsonl`. The lead reads new lines at Step 3.0 below. Agents themselves write `<root>/.my-harness/logs/agents.log` via `agent-log.sh`.

## Step 0 — Start the shared Codex daemon

Invoke the `harness-codex-daemon` skill with action `start`. Idempotent. Best-effort: on failure lanes fall back to per-call stdio.

## Step 1 — List pending tasks

```bash
bash "$SKILL_DIR/scripts/list-pending-issues.sh" "$ROOT" > /tmp/harness-pending.tsv
```

Capture silently. Output is TSV: `<id>\t<lane>\t<owned_files_csv>\t<title>`. Pending = `status: pending` (FS) or `state: open AND label: ready` (GitHub). `status: in_progress` is filtered out so `/loop` wakeups never re-dispatch the same task. Teammates run `build-dev-env.sh` themselves on ASSIGNMENT — no project-root warmup (project root holds only `.bare/` + worktrees).

## Step 2 — Create or reuse the team

```bash
TEAM_STATE=$(bash "$SKILL_DIR/scripts/check-team-exists.sh")  # stdout: absent | present | corrupt
```

- `absent` → `TeamCreate({team_name: "harness-team", description: "4-lane parallel implementation team."})`. Do NOT create teammates here — that happens lane-by-lane in Step 3.
- `present` → straight to Step 3.
- `corrupt` → stop. The script printed recovery instructions on stderr (delete `~/.claude/teams/harness-team/` and start a fresh session); surface them.

Empty teams are valid.

## Step 3 — Parallel dispatch loop

In-memory state: `pending_queue` (task ids), `lane_status` (`{ lane-N: "absent" | "idle" | { issue, phase } | "paused-*" }`, init all `"absent"`), `completed` (list of `{issue, pr_url, commit_sha}`).

**Spawn is sequential, dispatch is parallel.** Lanes added one at a time (resource-gated); once spawned they run concurrently; the lead never blocks on one lane.

### Step 3.0 — Anomaly check (BEFORE 3a, every iteration)

```bash
ANOM="$ROOT/.my-harness/logs/anomalies.jsonl"
if [ -f "$ANOM" ]; then
  STATE="$ROOT/.my-harness/logs/anomalies.offset"
  OFFSET="$(cat "$STATE" 2>/dev/null || echo 0)"
  NEW="$(tail -c +"$((OFFSET + 1))" "$ANOM" 2>/dev/null)"
  wc -c < "$ANOM" > "$STATE" 2>/dev/null
fi
```

For each new anomaly `{ts, kind, agent, detail}`, apply this table deterministically (no free-form interpretation):

| `kind` | Intervention |
|---|---|
| `stagnation` | `SendMessage(agent, "STATUS_PING: no event for >10 min. Report current status now.")`. Second stagnation within 10 min → escalate: `Lane <N> <agent> is unresponsive (stagnation x2). Suggest: kill the worktree and re-dispatch.` |
| `repeated-blocked` | Same blocker ≥3 times. Mark lane `paused-<blocker>`, surface ONE user message with the recovery steps from the matching handling section. No auto-retry. |
| `codex-exec-failure` | 3+ consecutive non-zero exits. `SendMessage(agent, "FALLBACK: switch to claude mode for this issue. Codex sandbox/auth is unhealthy.")`. Set `USE_CODEX_<ROLE>=no` in-memory ONLY for this issue (do NOT modify `.config`). |
| `codex-no-op` | `engineer-N impl-done changed=0`. `SendMessage(engineer-N, "FIX: codex-exec finished but no files changed. Re-read the brief and state which files you will modify before running codex-exec again.")` |
| `suffixed-name` | Critical. STOP all dispatch. Surface: `Suffixed teammate detected (<name>). Delete ~/.claude/teams/harness-team/ and restart Claude Code in dev/.` |

### 3a. Fill all available lanes (initial burst)

Until `pending_queue` is empty OR no more lanes can be assigned:

1. Pick the next dispatchable task from the front of the queue (3a-rules below).
2. Decide target lane:
   - Preferred lane `idle` → use.
   - Preferred lane `absent` → use (spawn below).
   - Preferred lane busy → defer, try next candidate.
   - No preferred lane → lowest-numbered `idle`, else lowest-numbered `absent`.
3. If target is `absent`, run spawn gate:
   ```bash
   bash "$SKILL_DIR/scripts/spawn-lane-decision.sh" <N> "$ROOT"
   # stdout: DECISION=<SPAWN|SKIP|REFUSE> LANE=<N> NAMES=... REASON=...
   ```
   - `SPAWN` → call `Agent({})` for each name in `NAMES`, **one at a time**, awaiting `[<name> status=ready]` before the next. Template:
     ```
     Agent({
       team_name: "harness-team",
       name: "analyst-N",        // or engineer-N / e2e-reviewer-N / reviewer-N
       subagent_type: "harness-analyst",   // or harness-engineer / -e2e-reviewer / -reviewer
       prompt: "You are analyst-N of lane-N. Acknowledge with [analyst-N status=ready] and idle. Do not Read, run Bash, or call any tool until you receive an ASSIGNMENT."
     })
     ```
     After all four ack → `lane_status["lane-N"] = "idle"`.
   - `SKIP` → teammates already in config (e.g. `/loop` re-entry). Set `idle`. Do NOT call `Agent({})`.
   - `REFUSE` resource pressure → stop the burst. Running lanes keep running; tasks wait. Surface REASON in one short line.
   - `REFUSE` corruption (`partial-lane` / `corrupt-team`) → stop entirely with recovery instructions.
4. Create the lane worktree and dispatch (non-blocking):
   ```bash
   bash "$SKILL_DIR/scripts/harness-worktree.sh" add "$ROOT" "<id>" "<slug>"
   ```
   ```
   SendMessage({
     to: "analyst-N",
     content: "ASSIGNMENT
       root: <ROOT>
       issue: #<X>
       branch: feat/<X>-<slug>
       worktree: <ROOT>/lanes/feat-<X>-<slug>/
       owned_files: [<list>]
       language: <LANG>
       Begin Step 1 (brief production), then dispatch engineer-N → e2e-reviewer-N → reviewer-N. After all gates pass, run git commit + push + gh pr create yourself. Final completion message: [analyst-N issue=#<X> status=pr-created pr=<URL>]."
   })
   ```
   `lane_status["lane-N"] = { issue: X, phase: "1-brief" }`. **Loop back to step 1 immediately** — do not wait for the analyst.

### 3a-rules (preferred-lane / owned_files)

- **Preferred lane**: task's `lane` field is where it was authored to land. Defer rather than send to a different lane.
- **owned_files conflict**: defer if any active lane's task shares paths (glob match) with the candidate.
- **`owned_files` is a dispatch-time gate only.** Once a task is in flight, engineer-N may touch any file the brief requires, including shared config. Do not police running lanes against `owned_files`.

### 3b. Wait for any completion

When the burst exits with at least one busy lane, wait for inbound `SendMessage`. Possible messages:

```
[analyst-N issue=#X step=<step> status=<state>]
[analyst-N issue=#X status=pr-created pr=https://...]
[lane=N issue=#X status=blocked-codex-auth role=<engineer|e2e|reviewer> rescue=<path>]
[lane=N issue=#X status=blocked-disk-full]
[lane=N issue=#X status=blocked-workspace-not-ready details=<line>]
```

- `pr-created` → 3c.
- `blocked-codex-auth` → see "Codex auth handling".
- `blocked-disk-full` → see top.
- `blocked-workspace-not-ready` → mark lane `paused-workspace`, surface once: `Lane N (issue #X) needs an earlier monorepo-setup task to land first. After that PR merges into dev, say "resume lane N".` No auto-retry. Other lanes continue.
- Intermediate `step=<step> status=<state>` → just update bookkeeping; do not interrupt other lanes.

### 3c. Clear the finishing lane and refill it

On `status=pr-created`:

1. Send `/clear` to all four teammates in one message (four parallel SendMessage):
   ```
   SendMessage({ to: "analyst-N",      content: "DIRECTIVE: clear_context\nInvoke /clear, then ack [analyst-N status=cleared]." })
   SendMessage({ to: "engineer-N",     content: "DIRECTIVE: clear_context\nInvoke /clear, then ack [engineer-N status=cleared]." })
   SendMessage({ to: "e2e-reviewer-N", content: "DIRECTIVE: clear_context\nInvoke /clear, then ack [e2e-reviewer-N status=cleared]." })
   SendMessage({ to: "reviewer-N",     content: "DIRECTIVE: clear_context\nInvoke /clear, then ack [reviewer-N status=cleared]." })
   ```
2. Wait for the four `cleared` acks (other lanes keep working).
3. Remove the worktree:
   ```bash
   bash "$SKILL_DIR/scripts/harness-worktree.sh" remove "$ROOT" "<id>" "<slug>"
   ```
4. `lane_status["lane-N"] = "idle"`.
5. **Refill this lane immediately** by re-running 3a's pick-and-dispatch — a freed lane is back to work without waiting for others.
6. Return to 3b.

### 3d. Loop exit

When `pending_queue` is empty AND every lane is `idle` or `absent`, print the status table (Output format below) and ask via `AskUserQuestion`: continue, or shut down.

## Step 4 — Shutdown

Send `shutdown_request` to every current teammate in one message, await `shutdown_response`, then `TeamDelete({ team_name: "harness-team" })`. Stop the shared Codex daemon (`harness-codex-daemon` skill, action `stop`, best-effort). Print final summary.

## Codex auth failure handling

On `[lane=N issue=#X status=blocked-codex-auth role=<engineer|e2e|reviewer> rescue=<path>]`:

1. Mark lane `paused-codex-auth` (NOT idle — work unfinished).
2. ```bash
   RESCUE_SESSION_ID=$(jq -r '.session_id' "<rescue>")
   RESCUE_REASON=$(jq -r '.reason' "<rescue>")
   ```
3. Tell the user:
   ```
   Lane N (issue #X, role=<role>) paused — Codex auth (<RESCUE_REASON>).
     - login-expired / preflight-not-logged-in: run `codex login`, say "resume lane N".
     - subscription-or-quota: renew or set USE_CODEX_<ROLE>=no in .my-harness/.config, say "resume lane N".
   ```
4. On `resume lane N`:
   - `bash scripts/check-codex-auth.sh` to confirm.
   - `SendMessage(analyst-N, "RESUME\nROLE=<role>\nINHERITED_SESSION_ID=<RESCUE_SESSION_ID>")` so analyst-N forwards to the affected teammate.

## Stateless across `/clear` of the lead

When the lead context gets too heavy, write dispatch state to `<ROOT>/.my-harness/team-state.json`:

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

Tell user to `/clear` the lead and re-invoke `/harness-team-lead`. On re-entry, `check-team-exists.sh` → `present`, read `team-state.json` and resume. Do NOT re-create the team. `spawn-lane-decision.sh` returns `SKIP` for already-spawned lanes.

## Hard rules (recap)

- ≤ 4 lanes. Tasks queue when all four are busy.
- Teammates persistent within a session. `/clear` between issues; never destroy + recreate mid-session (except Step 4).
- One issue per lane at a time. No second issue until `pr-created` AND all four `cleared`.
- Lead talks only to analyst-N during processing. Exceptions: Step 3c clear sweep, Step 4 shutdown.
- No nested teammates. No teammate creates teammates.
- Every `Agent({})` is preceded by `spawn-lane-decision.sh` returning `SPAWN`.

## Output format (status table)

```
[team-lead summary]
team: harness-team (lanes spawned: 2 of 4)
lanes:
  lane-1  idle              last: #41 → https://github.com/.../pull/12
  lane-2  in-progress #47   active=engineer-2
  lane-3  absent
  lane-4  absent
queue:    [#50, #51, #52]
next: dispatching #50 → lane-1
```
