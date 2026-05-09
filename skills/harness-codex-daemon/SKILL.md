---
name: harness-codex-daemon
description: Lifecycle controller for the shared `codex app-server` daemon. Provides start / stop / status / restart / logs / doctor as the single canonical entry point. Other skills (harness-team-lead, harness-codex-consult, etc.) MUST invoke this skill instead of running `skills/harness-codex-daemon/scripts/codex-daemon.sh` inline — that keeps the bash boilerplate out of the caller's context. Fires when the user says "start the codex daemon", "stop the codex daemon", "share codex across lanes", or when an orchestrator is opening / closing a parallel work session.
---

# harness-codex-daemon

Single source of truth for talking to the shared Codex daemon. Wraps
`skills/harness-codex-daemon/scripts/codex-daemon.sh` so callers can invoke this skill once instead of
quoting bash blocks. The underlying script supports stdin-less, side-effect-
free idempotent operation: `start` is a no-op when already running, `stop` is
a no-op when not running.

## When to use

| Caller | Action | When |
|--------|--------|------|
| `harness-team-lead` | `start` | At the top of a /harness-team-lead session, before issue dispatching |
| `harness-team-lead` | `stop` | On Step 4 shutdown (best-effort) |
| `harness-codex-consult` | (none) | The daemon is auto-detected by `codex-app-server-call.py`; no extra skill call needed |
| User direct | `status` / `logs` / `doctor` | Debugging or sanity checking |

## Why a daemon at all

Each `codex-ask.sh` call without the daemon spawns a fresh `codex app-server`
Node process. With a 16-teammate Agent Teams team running 4 lanes in parallel
that pile-up is measurable (3 concurrent lanes: 271 MB peak across 4 codex
processes; with the daemon: 120 MB peak across 2 — 55% reduction). The daemon
listens on `ws://127.0.0.1:7373` (loopback, no auth). Conversations stay
isolated by `threadId` — sharing the daemon does NOT share conversation
context across lanes.

If the daemon is down, `codex-app-server-call.py` falls back to per-call stdio
mode automatically, so this skill is best-effort: a failure to start does not
break the harness, it just removes the memory savings.

All actions are thin wrappers in `skills/harness-codex-daemon/scripts/`.
Invoke them via bash; do not inline the daemon path resolution.

## Action: start

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-codex-daemon/scripts/codex-daemon.sh" start
```

Exit 0 always means "the harness can proceed" — even if daemon failed to
start, lanes fall back to stdio mode. Read the printed status line to know
if the daemon is actually up.

## Action: stop

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-codex-daemon/scripts/codex-daemon.sh" stop
```

Best-effort. Safe to run multiple times. Skipping stop is fine — the daemon
will keep running and be reused on the next /harness-team-lead invocation
within the same session.

## Action: status

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-codex-daemon/scripts/codex-daemon.sh" status
```

Exit 0 when running and ready (`/readyz` returns 200), 1 when not running,
2 when pid alive but socket / port file is broken (run `restart`).

## Action: restart

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-codex-daemon/scripts/codex-daemon.sh" restart
```

`stop` + `start`. Use when daemon state files are corrupted.

## Action: doctor

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-codex-daemon/scripts/codex-daemon.sh" doctor
```

Probes `initialize` end-to-end through the Python SDK. Use when `status` is
green but lanes report unexpected timeouts. Requires either the Nix dev shell
to be active (provides `$MY_HARNESS_CODEX_PY`) or
`scripts/install-codex-sdk.sh` to have been run.

## Action: logs

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-codex-daemon/scripts/codex-daemon.sh" logs
```

`tail -f` of `~/.codex/my-harness-daemon.log`. Press Ctrl-C to detach.

## Hard rules

- Never call `codex-daemon.sh` directly from another skill's body — invoke
  this skill (`harness-codex-daemon`) instead. The point is to keep the
  bash quoting out of caller skills' contexts.
- The daemon is per-user, not per-project. One running daemon serves all
  projects on the machine. The `~/.codex/my-harness-daemon.{port,pid,log}`
  state files live under `$HOME/.codex/`.
- Override the home for testing with `MY_HARNESS_CODEX_DAEMON_HOME=...`
  (e.g. CI sandboxes); override the port with `MY_HARNESS_CODEX_DAEMON_PORT`.
