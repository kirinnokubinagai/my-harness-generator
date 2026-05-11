---
name: harness-codex-daemon
description: Lifecycle controller for the shared `codex app-server` daemon. Provides start / stop / status / restart / logs / doctor as the single canonical entry point. `harness-team-lead` invokes this skill instead of running `skills/harness-codex-daemon/scripts/codex-daemon.sh` inline so the bash boilerplate stays out of the caller's context. Fires when the user says "start the codex daemon", "stop the codex daemon", "share codex across lanes", or when an orchestrator is opening / closing a parallel work session.
---

# harness-codex-daemon

Wraps `skills/harness-codex-daemon/scripts/codex-daemon.sh` so callers don't quote bash blocks. The underlying script is idempotent: `start` is a no-op when already running, `stop` is a no-op when not running.

## When to use

| Caller | Action | When |
|---|---|---|
| `harness-team-lead` | `start` | Top of a `/harness-team-lead` session, before issue dispatch |
| `harness-team-lead` | `stop` | Step 4 shutdown (best-effort) |
| `codex-ask.sh` / `codex-exec.sh` callers | (none) | Daemon auto-detected by `codex-app-server-call.py`; no extra call needed |
| User direct | `status` / `logs` / `doctor` | Debugging |

## Why a daemon

Without it, every `codex-ask.sh` call spawns a fresh `codex app-server` Node process — measurable pile-up under 4-lane parallel load. The daemon listens on `ws://127.0.0.1:7373` (loopback, no auth) and shares the process across all callers. Conversations stay isolated by `threadId` — sharing the daemon does NOT share conversation context across lanes.

If the daemon is down, `codex-app-server-call.py` falls back to per-call stdio automatically. This skill is best-effort: a failed start does not break the harness, it just removes the memory savings.

## Actions

All actions resolve `$D` once:

```bash
D="${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/skills/harness-codex-daemon/scripts/codex-daemon.sh"
```

- `bash "$D" start` — exit 0 always means "harness can proceed". Read the printed status line to know if the daemon actually came up.
- `bash "$D" stop` — best-effort; safe to run multiple times. Skipping `stop` is fine — the daemon is reused on the next session.
- `bash "$D" status` — exit 0 when running + `/readyz` green; 1 when not running; 2 when pid alive but socket / port file broken (run `restart`).
- `bash "$D" restart` — `stop` + `start`. Use when state files are corrupted.
- `bash "$D" doctor` — probes `initialize` end-to-end through the Python SDK. Use when `status` is green but lanes report timeouts. Needs `$MY_HARNESS_CODEX_PY` (from the Nix dev shell) or `scripts/install-codex-sdk.sh` run.
- `bash "$D" logs` — `tail -f` of `~/.codex/my-harness-daemon.log`. Ctrl-C to detach.

## Hard rules

- Never call `codex-daemon.sh` directly from another skill's body — invoke this skill instead. Keeps bash quoting out of caller contexts.
- One daemon per user (not per project). State files live under `$HOME/.codex/my-harness-daemon.{port,pid,log}`.
- Override the home for testing: `MY_HARNESS_CODEX_DAEMON_HOME=...`. Override the port: `MY_HARNESS_CODEX_DAEMON_PORT=...`.
