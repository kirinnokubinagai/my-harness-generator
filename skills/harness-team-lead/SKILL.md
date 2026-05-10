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

The user is expected to launch Claude Code from `<project>/dev/` via `start-dev.sh` (or `cd <project>/dev && claude`). All scripts resolve `ROOT` to the project root (the directory holding `.bare/`) regardless of cwd, so passing `$(pwd)` is always safe.

```bash
ROOT="$(pwd)"
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}/skills/harness-team-lead"
bash "$SKILL_DIR/scripts/preflight.sh" "$ROOT" || exit $?
# After preflight, normalise ROOT for the rest of this session so messages and
# state files agree on a single canonical path.
__resolve_project_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}
ROOT="$(__resolve_project_root "$ROOT")"
```

`preflight.sh` checks: `.my-harness/.config` exists, ≥ 20 GB disk, ≥ 4 GB reclaimable RAM, swap ≤ 1 GB, compressor ≤ 6 GB, no `nix-collect-garbage` running. On any failure the script writes the remediation message to stderr — surface it to the user, do not retry silently.

## Hard prohibitions (non-negotiable)

- **Never call `Agent({name: X})` if `X` is already a member of `harness-team`.** Claude Code's runtime auto-disambiguates name collisions by suffixing (`X-2`, `X-3`, ...), which produces a corrupt team that can no longer be reasoned about. The `spawn-lane-decision.sh` gate (Step 3) is the only authorized source of new-spawn permission — call it before every `Agent({})`.
- **Never spawn a 5th lane.** Lanes are 1..4. Tasks queue when no lane is free.
- **Never invoke `nix-collect-garbage` / `nix-store --gc` from this skill.** Disk-full conditions are reported to the user; the user runs cleanup externally.
- **Never spawn long-running background bash** (`nohup ... &`).
- **Never `TeamDelete` mid-session** to "reset" a corrupt team. Surface the corruption to the user with the recovery instructions.

<!-- >>> TEST-LOG (REMOVE AFTER DEBUGGING) -->

## TEMPORARY — test logging

Every script writes to `<ROOT>/.my-harness/logs/harness-test.log`. The lead must mirror `Agent({})` / `TeamCreate` / `TeamDelete` calls to the same file:

```bash
printf '[%s] [lead] %s name=%s\n' "$(date -u +%FT%TZ)" BEFORE_AGENT "<name>" \
  >> "$ROOT/.my-harness/logs/harness-test.log"
# Agent({...}) here
printf '[%s] [lead] %s name=%s\n' "$(date -u +%FT%TZ)" AFTER_AGENT "<name>" \
  >> "$ROOT/.my-harness/logs/harness-test.log"
```

Removal once debugging is complete:

```bash
grep -rln 'TEST-LOG' "$CLAUDE_PLUGIN_ROOT/skills/harness-team-lead" | while read -r f; do
  awk '/TEST-LOG/{f=!f; next} !f' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

<!-- <<< TEST-LOG -->

## Disk-full handling

If any analyst-N reports `[lane=N issue=#X status=blocked-disk-full ...]` (or any teammate sends `ENOSPC`):

1. Mark the lane `paused-disk-full` in dispatch state.
2. Send one message to the user: `Lane N blocked by ENOSPC. Free disk space, then say "resume lane N".`
3. Do not start any cleanup ourselves. Do not retry until the user says `resume lane N`.

## Step 0 — Start the shared Codex daemon

Invoke the `harness-codex-daemon` skill with action `start`. Idempotent: no-op if already running. The daemon is a single Codex `app-server` listening on `ws://127.0.0.1:7373` shared across lanes, so 4 concurrent Codex calls collapse onto one process. If startup fails, lanes fall back to per-call stdio — best-effort, not a precondition.

## Step 0.5 — Pre-build the project-root devshell (warmup)

```bash
bash "$SKILL_DIR/scripts/build-dev-env.sh" "$ROOT" || exit $?
```

Pre-evaluates the master `flake.nix` once so subsequent per-lane builds reuse `/nix/store` derivations and finish in seconds. The script is content-hash-cached and idempotent. Each teammate later runs the same script against its own worktree (which may have lane-local `flake.nix` edits) and uses the returned wrapper as `"$DEVSH" <command>`.

## Step 1 — List pending tasks

```bash
bash "$SKILL_DIR/scripts/list-pending-issues.sh" "$ROOT" > /tmp/harness-pending.tsv
```

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

## Step 3 — Dispatch loop

In-memory state:
- `pending_queue` — task ids waiting for a lane
- `lane_status` — `{ "lane-1": "idle" | { "issue": <id>, "phase": <state> } | "paused-..." | "absent", ... }`
- `completed` — list of `{issue, pr_url, commit_sha}`

Initialize each lane's status to `"absent"` (not yet spawned). Loop until `pending_queue` is empty AND every lane is `idle` or `absent`.

### 3a. Pick a candidate task and a target lane

For each task at the front of `pending_queue`:

1. **Preferred lane**: if the task has a `lane` field and that lane is `idle`, use it. If that lane is `absent`, use it (the lane will be added in 3b). If that lane is busy, defer this task and try the next.
2. **No preferred lane**: pick any `idle` lane. If none, pick any `absent` lane (it will be added in 3b).
3. **owned_files conflict** check: if any active lane is processing a task whose `owned_files` overlap with the candidate, defer.
4. If no candidate fits, wait for a lane to free up (Step 3d).

### 3b. Ensure the target lane exists (add lanes one at a time)

If `lane_status["lane-N"] == "absent"`, the four teammates have not been spawned yet. Run the gate:

```bash
bash "$SKILL_DIR/scripts/spawn-lane-decision.sh" N "$ROOT"
# stdout (key=value lines):
#   DECISION=<SPAWN|SKIP|REFUSE>
#   LANE=N
#   NAMES=analyst-N engineer-N e2e-reviewer-N reviewer-N
#   REASON=...
```

Act mechanically on `DECISION`:

- **`SPAWN`** — call `Agent({})` for each name in `NAMES`, **one call at a time**, waiting for each `[<name> status=ready]` ack before sending the next. Spawn template:
  ```
  Agent({
    team_name: "harness-team",
    name: "analyst-N",        // or engineer-N / e2e-reviewer-N / reviewer-N
    subagent_type: "harness-analyst",   // or harness-engineer / harness-e2e-reviewer / harness-reviewer
    prompt: "You are analyst-N of lane-N. Acknowledge with [analyst-N status=ready] and idle. Do not Read, run Bash, or call any tool until you receive an ASSIGNMENT message."
  })
  ```
  When all four have acked, mark `lane_status["lane-N"] = "idle"` and proceed to 3c.
- **`SKIP`** — the four teammates are already in the team config (e.g. after `/loop` re-entry). Mark `lane_status["lane-N"] = "idle"` and proceed to 3c. Do NOT call `Agent({})` — that would trigger the suffix bug.
- **`REFUSE`** — surface `REASON` to the user. If the reason is resource pressure, leave the task in the queue and wait for an existing lane to finish (a finishing lane frees ~4 GB; the next 3a iteration retries this task). If the reason is corruption (`corrupt-team` / `partial-lane`), stop entirely.

If `lane_status["lane-N"]` is already `idle` (the lane is spawned and free), skip the gate and proceed directly to 3c.

### 3c. Create the worktree, then assign

```bash
bash "$SKILL_DIR/scripts/harness-worktree.sh" add "$ROOT" "<id>" "<slug>"
# Idempotent. Branches off origin/dev so the worktree starts on the latest peer-merged commits.
```

Send the assignment to that lane's analyst-N (and only the analyst — analyst-N dispatches the rest internally):

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

Update `lane_status["lane-N"] = { issue: X, phase: "1-brief" }`.

### 3d. Receive progress messages

Lanes report only via analyst-N during processing:

```
[analyst-N issue=#X step=<step> status=<state>]
[analyst-N issue=#X status=pr-created pr=https://...]
[lane=N issue=#X status=blocked-codex-auth role=<engineer|e2e|reviewer> rescue=<path>]
[lane=N issue=#X status=blocked-disk-full]
```

Update `lane_status` accordingly. On `pr-created`, proceed to 3e. On `blocked-codex-auth`, see "Codex auth handling" below. On `blocked-disk-full`, see top of file.

### 3e. Clear the lane after PR completes

When analyst-N reports `status=pr-created`, send the clear directive to all four teammates of that lane in one message (four parallel SendMessage calls):

```
SendMessage({ to: "analyst-N",       content: "DIRECTIVE: clear_context\nInvoke /clear in your own session, then ack with [analyst-N status=cleared ready-for-issue]." })
SendMessage({ to: "engineer-N",      content: "DIRECTIVE: clear_context\nInvoke /clear, then ack with [engineer-N status=cleared ready]." })
SendMessage({ to: "e2e-reviewer-N",  content: "DIRECTIVE: clear_context\nInvoke /clear, then ack with [e2e-reviewer-N status=cleared ready]." })
SendMessage({ to: "reviewer-N",      content: "DIRECTIVE: clear_context\nInvoke /clear, then ack with [reviewer-N status=cleared ready]." })
```

Wait for all four `cleared` acks. Then remove the lane worktree:

```bash
bash "$SKILL_DIR/scripts/harness-worktree.sh" remove "$ROOT" "<id>" "<slug>"
# Idempotent. Also deletes the local feature branch (the remote has the commits via the PR).
```

Mark `lane_status["lane-N"] = "idle"` and continue from 3a.

### 3f. Loop until queue is empty AND all lanes are idle

When done, print a status table to the user (lane / last issue / PR URL / status), then ask via `AskUserQuestion`: continue with another batch of pending issues, or shut down the team.

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
