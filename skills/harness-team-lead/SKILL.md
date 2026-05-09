---
name: harness-team-lead
description: 4-lane parallel implementation orchestrator using Claude Code Agent Teams. Creates ONE team (`harness-team`) with 16 persistent teammates at session start (4 lanes × 4 roles = analyst-1..4, engineer-1..4, e2e-reviewer-1..4, reviewer-1..4) and keeps them alive for the whole session. team-lead dispatches one issue at a time to whichever lane is idle by SendMessage to that lane's analyst. After each issue completes, team-lead sends `/clear` to all 4 teammates of that lane (fresh-agent-per-issue). Fires when the user says "/harness-team-lead", "start the team", "next batch of issues", or similar. Required after /my-harness-init has finished setup.
---

# /harness-team-lead

This is the **only ongoing-development entry point** users invoke after `/my-harness-init` completes. All 4-lane parallel implementation work runs through this skill.

The skill is the **team lead** in a Claude Code Agent Teams session. It creates one team (`harness-team`) with **16 persistent teammates** (4 lanes × 4 roles), then dispatches issues to lanes one at a time. Teammates stay alive for the whole session; `/clear` is sent to all 4 teammates of a lane after their issue is complete, never destruction-and-recreation.

## Prerequisite — Agent Teams must be enabled

This skill **requires** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Without it, `TeamCreate` / `SendMessage` / `TaskList` are not available and the architecture cannot run.

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-team-lead"
bash "$SKILL_DIR/scripts/check-agent-teams-enabled.sh" || exit $?
```

If the script exits non-zero, surface the remediation message to the user and stop.

## Precondition — project must be initialized

```bash
ROOT="$(pwd)"
if [ ! -f "$ROOT/.my-harness/.config" ]; then
  echo "Error: .my-harness/.config not found. Run /my-harness-init first."
  exit 1
fi
source "$ROOT/.my-harness/.config"
```

If `.config` is missing, tell the user "Run `/my-harness-init` first" and stop.

## Precondition — resource pre-flight (HARD GATE, never skip)

This skill spawns 16 in-process teammates. On a memory-constrained or disk-constrained host, that is enough to deadlock the kernel (verified: a 16 GB Mac at 95% Data-volume capacity panics within minutes once 16 teammates start working). Refuse to proceed if any of the gates fail. Do **not** try to fix the resource problem from inside this skill — escalate to the user.

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-team-lead"
bash "$SKILL_DIR/scripts/preflight.sh" "$ROOT" || exit $?
```

The script (`skills/harness-team-lead/scripts/preflight.sh`) checks four gates:

1. `.my-harness/.config` exists (project initialized)
2. Data volume ≥ 30 GB available
3. Free RAM ≥ 1 GB, compressor < 4 GB
4. No `nix-collect-garbage` currently running

On any failure, the script writes the remediation steps to stderr and exits non-zero. **Do not silently retry — surface the message to the user.**

## Hard prohibitions (idempotency under /loop wakeup)

This skill MUST be safe to re-enter (e.g. via `/loop`-driven wakeups). Each wakeup re-evaluates state but must not spawn duplicate work. Explicit prohibitions:

- **Never** invoke `nix-collect-garbage` / `nix-store --gc` from inside this skill. Lane blocks caused by ENOSPC are reported to the user (see "Disk-full handling" below); the user runs cleanup externally.
- **Never** spawn long-running background bash (`nohup ... &`) from inside this skill. Step 0 explicitly defers daemon lifecycle to the `harness-codex-daemon` skill, which is itself idempotent.
- **Never** call `TeamCreate` if `~/.claude/teams/harness-team/config.json` already exists — go straight to dispatch in Step 3.
- **Never** call `Agent({...})` for a `name` that is already a member of `harness-team` (verify via the existing config.json's `members[].name`).

## Disk-full handling

When any analyst-N reports `[lane=N issue=#X status=blocked-disk-full ...]` (or any teammate sends a message containing `ENOSPC`):

1. Mark the lane `paused-disk-full` in `team-state.json`.
2. **Send one (and only one) message to the user**: "Lane N blocked by ENOSPC. Run `bash $HOME/harness-monitor/cleanup.sh` (or free disk manually), then say 'resume lane N'."
3. **Do not** start any cleanup ourselves. **Do not** retry until the user says "resume lane N".
4. On wakeup re-entry: if `lane_status[N].phase == "paused-disk-full"`, do nothing for that lane — wait for the explicit user resume.

## Step 0 — Start the shared Codex daemon

Invoke the **`harness-codex-daemon`** skill with action `start`. That skill
encapsulates the bash boilerplate so this orchestrator stays high-level and
its context window stays small. The daemon (`codex app-server` listening on
`ws://127.0.0.1:7373`) is shared by every lane, so 16 concurrent codex calls
collapse onto one Codex process — measured 55% RAM reduction at 3 lanes,
~85% projected at 16. Skill is idempotent: no-op if already running.

The daemon survives `/clear` of the lead session and is reused across
`/harness-team-lead` invocations until explicitly stopped in Step 4. If it
fails to start, lanes fall back to per-call stdio mode automatically — this
step is best-effort, not a precondition.

## Step 1 — Determine issue source

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-team-lead"
bash "$SKILL_DIR/scripts/list-pending-issues.sh" "$ROOT" > /tmp/harness-pending.tsv
```

The script (`skills/harness-team-lead/scripts/list-pending-issues.sh`) auto-detects `USE_GITHUB_ISSUES` from `.my-harness/.config` and emits one `<id>\t<title>` line per pending issue (FIFO order). The team processes 4 in parallel at any moment (one per lane); the rest queue.

## Step 2 — Create the team and 16 teammates (once per session)

**Idempotency check (mandatory, run every entry — including /loop wakeups)**:

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-team-lead"
TEAM_STATE=$(bash "$SKILL_DIR/scripts/check-team-exists.sh")
# stdout is one of: "skip" | "create" | "broken"
```

- `skip`   — team is fully populated. **Skip TeamCreate AND all 16 Agent calls**, go directly to Step 3.
- `create` — no team file. Run TeamCreate + 16 Agent (block below).
- `broken` — team file exists but membership is wrong. **Stop and report to user**; do not auto-delete (`TeamDelete` aborts running teammates and spawns N new processes).

If `create`:

```
TeamCreate({
  team_name: "harness-team",
  description: "4-lane parallel implementation team. 16 teammates: 4 roles × 4 lanes. analyst-N orchestrates lane-N and owns git operations; engineer-N implements; e2e-reviewer-N runs Playwright/Maestro; reviewer-N runs the convention checklist."
})
```

Then **create all 16 teammates in a single message with parallel Agent calls** (4 roles × 4 lanes):

```
Agent({ team_name: "harness-team", name: "analyst-1",       subagent_type: "harness-analyst",       prompt: "You are analyst-1 of lane-1. Read <ROOT>/.my-harness/.config for runtime flags (LANG, USE_CODEX*) when you need them. Acknowledge and idle." })
Agent({ team_name: "harness-team", name: "engineer-1",      subagent_type: "harness-engineer",      prompt: "You are engineer-1 of lane-1. Read <ROOT>/.my-harness/.config for runtime flags when needed." })
Agent({ team_name: "harness-team", name: "e2e-reviewer-1",  subagent_type: "harness-e2e-reviewer",  prompt: "You are e2e-reviewer-1 of lane-1. Read <ROOT>/.my-harness/.config for runtime flags when needed." })
Agent({ team_name: "harness-team", name: "reviewer-1",      subagent_type: "harness-reviewer",      prompt: "You are reviewer-1 of lane-1. Read <ROOT>/.my-harness/.config for runtime flags when needed." })

Agent({ team_name: "harness-team", name: "analyst-2",       subagent_type: "harness-analyst",       prompt: "You are analyst-2 of lane-2. ..." })
Agent({ team_name: "harness-team", name: "engineer-2",      subagent_type: "harness-engineer",      prompt: "You are engineer-2 of lane-2. ..." })
Agent({ team_name: "harness-team", name: "e2e-reviewer-2",  subagent_type: "harness-e2e-reviewer",  prompt: "You are e2e-reviewer-2 of lane-2. ..." })
Agent({ team_name: "harness-team", name: "reviewer-2",      subagent_type: "harness-reviewer",      prompt: "You are reviewer-2 of lane-2. ..." })

# ... repeat for lane-3 (4 more teammates) and lane-4 (4 more teammates), 16 total
```

Wait for each teammate's `[<role>-<N> status=ready]` ack. When all 16 have acked, the team is up.

**Hard rule: exactly 4 lanes, exactly 16 teammates. Never create lane-5 or higher; never create a 5th teammate of any role.** When more issues are pending than 4 lanes can hold, they queue — they do not get a 5th lane.

## Step 3 — Dispatch loop

Maintain in-memory state:
- `pending_queue`: list of issue numbers waiting for a lane
- `lane_status`: `{ "lane-1": "idle" | { "issue": <#>, "phase": <state> }, "lane-2": ..., ... }`
- `completed`: list of `{issue, pr_url, commit_sha}`

Loop until `pending_queue` is empty AND all lanes are idle:

### 3a. Wait for an idle lane

A lane-N is idle when:
- All 4 of its teammates (analyst-N, engineer-N, e2e-reviewer-N, reviewer-N) have most recently sent `status=ready` (just initialized) or `status=cleared` (just /clear'd after an issue), AND
- `lane_status["lane-N"] == "idle"` in our bookkeeping.

If no lane is idle, wait for inbound `SendMessage` from any analyst-N. The Agent Teams runtime delivers these to the lead.

### 3b. Find the next dispatchable issue (with conflict avoidance)

From `pending_queue`, pop the next issue. Check **file conflicts** against currently-active lanes:

- Read the candidate issue's `owned_files` (from front matter when `USE_GITHUB_ISSUES=no`, or from issue body section when `=yes`).
- If any active lane is processing an issue with overlapping `owned_files`, **defer this issue back to the queue** and try the next candidate. This avoids merge conflicts during parallel implementation.
- If no candidate fits, wait for the next lane completion (back to 3a).

### 3c. Assign the issue to the idle lane

Send the assignment ONLY to that lane's analyst-N (analyst-N orchestrates the rest of the lane internally via SendMessage):

```
SendMessage({
  to: "analyst-N",
  type: "message",
  content: "ASSIGNMENT
  issue: #<X>
  branch: feat/<X>-<slug>
  worktree: <ROOT>/lanes/feat-<X>-<slug>/
  owned_files: [<list>]
  language: <LANG>
  Begin Step 1 (brief production). Then dispatch engineer-N, e2e-reviewer-N, reviewer-N via SendMessage. After all gates pass, run git commit + push + gh pr create yourself. Final completion message to me: [analyst-N issue=#<X> status=pr-created pr=<URL>]."
})
```

Update `lane_status["lane-N"] = { issue: X, phase: "1-brief" }`.

**You do NOT message engineer-N / e2e-reviewer-N / reviewer-N directly during processing.** analyst-N talks to them. You only talk to analyst-N (and to all 4 of the lane during the /clear sweep).

### 3d. Aggregate progress

While dispatching, also receive intermediate messages from running lanes. They come from analyst-N (the only teammate that talks to you during processing):

```
[analyst-N issue=#X step=1-brief status=ready brief=<path>]
[analyst-N issue=#X status=pr-created pr=https://...]
[lane=N issue=#X status=blocked-codex-auth role=<engineer|e2e|reviewer> rescue=<path>]
```

Update `lane_status` accordingly. On `pr-created`, proceed to 3e (clear the lane). On `blocked-codex-auth`, see "Codex auth failure handling" below.

### 3e. Clear the lane (after PR completes)

When analyst-N reports `status=pr-created`, send `/clear` to **all 4 teammates of that lane** (in a single message with 4 parallel SendMessage calls):

```
SendMessage({ to: "analyst-N",       type: "message", content: "DIRECTIVE: clear_context\nInvoke /clear in your own session, then ack with [analyst-N status=cleared ready-for-issue]." })
SendMessage({ to: "engineer-N",      type: "message", content: "DIRECTIVE: clear_context\nInvoke /clear, then ack with [engineer-N status=cleared ready]." })
SendMessage({ to: "e2e-reviewer-N",  type: "message", content: "DIRECTIVE: clear_context\nInvoke /clear, then ack with [e2e-reviewer-N status=cleared ready]." })
SendMessage({ to: "reviewer-N",      type: "message", content: "DIRECTIVE: clear_context\nInvoke /clear, then ack with [reviewer-N status=cleared ready]." })
```

Wait for all 4 cleared acks. Only then mark `lane_status["lane-N"] = "idle"` and proceed to 3a (the lane is now ready for its next issue).

### 3f. Loop until queue is empty AND all lanes idle

When all pending issues are done:
- Print a consolidated status table to the user (lane / last-issue / PR URL / status).
- Ask the user via `AskUserQuestion`: continue to next batch (more pending issues exist), or shut down the team.

## Step 4 — Shutdown

When the user agrees to stop or all conceivable batches are done, send `shutdown_request` to all 16 teammates (single message, 16 parallel calls). Wait for `shutdown_response` from each, then:

```
TeamDelete({ team_name: "harness-team" })
```

Stop the shared Codex daemon by invoking the **`harness-codex-daemon`**
skill with action `stop` (best-effort; safe to skip if the user wants it
to keep running for follow-up work).

Print a final summary to the user.

## Codex auth failure handling

When any lane reports `[lane=N issue=#X status=blocked-codex-auth role=<engineer|e2e|reviewer> rescue=<path>]` (forwarded by analyst-N from the affected role teammate):

1. Mark that lane as `paused` (do NOT mark idle — it has unfinished work).
2. Read the rescue JSON:
   ```bash
   RESCUE_FILE="<rescue_path>"
   RESCUE_SESSION_ID=$(jq -r '.session_id' "$RESCUE_FILE")
   RESCUE_REASON=$(jq -r '.reason' "$RESCUE_FILE")
   ```
3. Tell the user:
   ```
   Lane N (issue #X, role=<engineer|e2e|reviewer>) is paused — Codex auth/subscription issue (<RESCUE_REASON>).
   Action required:
     - login-expired / preflight-not-logged-in: run `codex login`, then say "resume lane N"
     - subscription-or-quota: renew subscription OR set USE_CODEX_<ROLE>=no in .my-harness/.config, then say "resume lane N"
   ```
4. On `"resume lane N"`:
   - Run `bash scripts/check-codex-auth.sh` to confirm logged-in.
   - SendMessage to analyst-N:
     ```
     RESUME
     ROLE=<engineer|e2e|reviewer>
     INHERITED_SESSION_ID=<RESCUE_SESSION_ID>
     analyst-N: please forward this to the affected teammate so it retries the failing call with this session id.
     ```
   - analyst-N forwards: `SendMessage({to: "<role>-N", content: "RESUME\nINHERITED_SESSION_ID=<id>\n<original task>"})`.
   - Codex's session is preserved server-side, so prior context resumes once the same session id is reused.

## Stateless across `/clear` of the lead session

If the lead session itself becomes too heavy, write the dispatch state to `<ROOT>/.my-harness/team-state.json`:

```json
{
  "team_name": "harness-team",
  "lane_status": {
    "lane-1": "idle",
    "lane-2": { "issue": 47, "phase": "engineer" },
    "lane-3": { "issue": 48, "phase": "reviewer" },
    "lane-4": "paused"
  },
  "pending_queue": [50, 51, 52],
  "completed": [{"issue": 41, "pr": "https://..."}, {"issue": 42, "pr": "https://..."}]
}
```

Tell the user to `/clear` the lead session and re-invoke `/harness-team-lead`. On re-invocation:
- If teammates are still alive (Agent Teams keeps teammates alive across lead `/clear` per official docs's persistent-teammate model) → re-read `team-state.json` and resume the dispatch loop. Do NOT re-create the team.
- If teammates were lost (Claude Code restart, etc.) → recreate the team from scratch (Step 2).

## Hard rules (non-negotiable)

- **Exactly 4 lanes × 4 roles = 16 teammates.** Never create a 17th teammate of any kind.
- **Teammates are persistent.** Created once, kept alive, `/clear`'ed between issues — never destroyed and recreated mid-session (except shutdown at end).
- **One issue per lane at a time.** Never assign a second issue to a lane before that lane reports `pr-created` AND all 4 teammates of that lane report `cleared`.
- **`/clear` all 4 teammates after every issue.** Never reuse a lane's context across issues. Never partial-clear (e.g., only clearing the analyst).
- **You only talk to analysts** during processing. analyst-N is the lane's foreman and dispatches engineer-N / e2e-reviewer-N / reviewer-N internally via SendMessage. The only exception is Step 3e (the post-issue clear sweep) and Step 4 (shutdown), where you message all 4 teammates of the affected lane(s).
- **No nested teammates.** No teammate creates another teammate. The team is fixed at 16 + lead.

## Output format (status report to user)

After each batch or on user request:

```
[team-lead summary]
team: harness-team (16 teammates: 4 lanes × 4 roles)
lanes:
  lane-1  idle (last: #41 → https://github.com/.../pull/12)
  lane-2  in-progress #47 active=engineer-2
  lane-3  in-progress #48 active=reviewer-3
  lane-4  paused     #49 stuck-on=engineer-4 reason=blocked-codex-auth
queue:    [#50, #51, #52]
codex_auth: paused (1 lane)
next: waiting on Codex login for lane-4
```
