#!/usr/bin/env bash
# Summary: Lifecycle manager for a shared `codex app-server` daemon listening
#          on a loopback WebSocket. When this daemon is running, every lane's
#          codex-ask.sh call is multiplexed onto the same Codex process —
#          eliminating per-call Node cold start while keeping conversations
#          isolated by `threadId` (no cross-lane context bleeding).
#
# Transport: --listen ws://127.0.0.1:PORT
#          The WebSocket transport (PR #11370) explicitly supports concurrent
#          clients and was tested with >10 simultaneous connections. The
#          earlier unix-socket attempt (--listen unix://) hits issue #19688
#          ("invalid opcode: 7" on UDS WebSocket handshake) and is not used.
#
# Subcommands:
#   start    Launch daemon if not already running
#   stop     Graceful shutdown
#   restart  stop + start
#   status   Show pid / port / liveness
#   logs     Tail the daemon log
#   doctor   Probe initialize over WebSocket end-to-end
#
# State files (override base via $MY_HARNESS_CODEX_DAEMON_HOME):
#   $HOME/.codex/my-harness-daemon.port   loopback port the daemon listens on
#   $HOME/.codex/my-harness-daemon.pid    daemon PID
#   $HOME/.codex/my-harness-daemon.log    daemon stdout+stderr
#
# codex-app-server-call.py auto-detects the port file and connects via the
# bundled Python SDK (codex_app_server_sdk.CodexClient.connect_websocket).
# Stop the daemon to fall back to stdio mode (one codex per call).

set -euo pipefail

DAEMON_HOME="${MY_HARNESS_CODEX_DAEMON_HOME:-$HOME/.codex}"
PORT_FILE="$DAEMON_HOME/my-harness-daemon.port"
PID_FILE="$DAEMON_HOME/my-harness-daemon.pid"
LOG_FILE="$DAEMON_HOME/my-harness-daemon.log"

DEFAULT_PORT="${MY_HARNESS_CODEX_DAEMON_PORT:-7373}"
READYZ_WAIT_TICKS=80    # 0.1s × 80 = 8s budget for /readyz to return 200
STOP_WAIT_TICKS=30      # 0.1s × 30 = 3s budget for graceful shutdown

is_pid_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

read_pid()  { [ -f "$PID_FILE"  ] && cat "$PID_FILE"  || return 1; }
read_port() { [ -f "$PORT_FILE" ] && cat "$PORT_FILE" || return 1; }

probe_ready() {
  local port="$1"
  curl -fs --max-time 1 "http://127.0.0.1:$port/readyz" >/dev/null 2>&1
}

cmd_status() {
  local pid port
  pid=$(read_pid 2>/dev/null  || true)
  port=$(read_port 2>/dev/null || true)
  if [ -z "$pid" ]; then
    echo "[codex-daemon] not running (no pid file)"
    return 1
  fi
  if ! is_pid_alive "$pid"; then
    echo "[codex-daemon] stale pid file (pid=$pid not alive); cleaning"
    rm -f "$PID_FILE" "$PORT_FILE"
    return 1
  fi
  if [ -z "$port" ] || ! probe_ready "$port"; then
    echo "[codex-daemon] pid=$pid alive but /readyz failed (port=${port:-unknown})"
    return 2
  fi
  echo "[codex-daemon] running"
  echo "  pid:  $pid"
  echo "  port: $port  (ws://127.0.0.1:$port)"
  echo "  log:  $LOG_FILE"
  return 0
}

cmd_start() {
  if cmd_status >/dev/null 2>&1; then
    local pid port; pid=$(read_pid); port=$(read_port)
    echo "[codex-daemon] already running (pid=$pid, port=$port)"
    return 0
  fi

  if ! command -v codex >/dev/null 2>&1; then
    echo "::error:: codex CLI not found in PATH" >&2
    return 127
  fi

  # Best-effort auth check. If `codex login` is missing/expired, the daemon
  # itself will still come up (the WS listener doesn't need auth), but every
  # turn will fail until the user runs `codex login`. Surface that now rather
  # than at first turn so the operator isn't surprised.
  local auth_check="${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/check-codex-auth.sh"
  if [ -x "$auth_check" ]; then
    local auth_state
    auth_state=$("$auth_check" 2>/dev/null || true)
    if [ "$auth_state" != "logged-in" ]; then
      echo "::warning:: codex auth state is '$auth_state' — turns will fail until \`codex login\` succeeds" >&2
    fi
  fi

  mkdir -p "$DAEMON_HOME"
  rm -f "$PID_FILE" "$PORT_FILE"

  # Truncate the log on each start so it never grows unbounded across
  # successive sessions. (No rotation — if you need history, copy the file
  # out before restarting the daemon.)
  : > "$LOG_FILE"

  local port="$DEFAULT_PORT"
  echo "[codex-daemon] starting on port $port (ws://127.0.0.1:$port)"
  nohup codex app-server --listen "ws://127.0.0.1:$port" \
    >"$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  echo "$port" > "$PORT_FILE"
  disown "$pid" 2>/dev/null || true

  # Wait for /readyz to return 200 (= listener is accepting clients).
  local i=0
  while [ "$i" -lt "$READYZ_WAIT_TICKS" ]; do
    if probe_ready "$port"; then
      echo "[codex-daemon] ready (pid=$pid, ws://127.0.0.1:$port)"
      echo "[codex-daemon] tail -f $LOG_FILE  to watch the daemon log"
      return 0
    fi
    if ! is_pid_alive "$pid"; then
      echo "::error:: daemon exited before /readyz responded. last log lines:" >&2
      tail -n 20 "$LOG_FILE" >&2 || true
      rm -f "$PID_FILE" "$PORT_FILE"
      return 1
    fi
    sleep 0.1
    i=$((i+1))
  done

  echo "::error:: /readyz did not respond within $((READYZ_WAIT_TICKS/10))s; check $LOG_FILE" >&2
  return 1
}

cmd_stop() {
  local pid; pid=$(read_pid 2>/dev/null || true)
  if [ -z "$pid" ]; then
    echo "[codex-daemon] not running"
    rm -f "$PORT_FILE"
    return 0
  fi
  if is_pid_alive "$pid"; then
    echo "[codex-daemon] stopping pid=$pid"
    kill -TERM "$pid" 2>/dev/null || true
    local i=0
    while [ "$i" -lt "$STOP_WAIT_TICKS" ]; do
      is_pid_alive "$pid" || break
      sleep 0.1
      i=$((i+1))
    done
    if is_pid_alive "$pid"; then
      echo "[codex-daemon] graceful timeout, sending SIGKILL"
      kill -KILL "$pid" 2>/dev/null || true
    fi
  else
    echo "[codex-daemon] pid=$pid was already gone"
  fi
  rm -f "$PID_FILE" "$PORT_FILE"
  echo "[codex-daemon] stopped"
}

cmd_restart() {
  cmd_stop || true
  cmd_start
}

cmd_logs() {
  if [ ! -f "$LOG_FILE" ]; then
    echo "::error:: log file not found: $LOG_FILE" >&2
    return 1
  fi
  exec tail -f "$LOG_FILE"
}

cmd_doctor() {
  cmd_status || return $?
  local port; port=$(read_port)
  # Resolve a python that has codex_app_server_sdk available. Order:
  #   1. $MY_HARNESS_CODEX_PY (set by flake.nix shellHook → nix python)
  #   2. ~/.codex/my-harness-venv/bin/python (set by install-codex-sdk.sh)
  #   3. Otherwise tell the user how to bootstrap.
  local sdk_py="${MY_HARNESS_CODEX_PY:-$HOME/.codex/my-harness-venv/bin/python}"
  if [ ! -x "$sdk_py" ]; then
    echo "[codex-daemon] doctor: no python with codex_app_server_sdk found"
    echo "[codex-daemon]   tried: $sdk_py"
    echo "[codex-daemon]   fix:   nix develop      (or scripts/install-codex-sdk.sh)"
    return 1
  fi
  echo "[codex-daemon] probing initialize via Python SDK ($sdk_py)..."
  "$sdk_py" - "$port" << 'PYEOF'
import asyncio, sys
from codex_app_server_sdk import CodexClient

port = sys.argv[1]

async def main():
    async with CodexClient.connect_websocket(
        url=f"ws://127.0.0.1:{port}",
        connect_timeout=5.0,
        request_timeout=10.0,
    ) as client:
        info = await client.initialize()
        server = info.server_info or {}
        print(f"[codex-daemon] doctor: OK (server={server.get('name','?')} v{server.get('version','?')})")

asyncio.run(main())
PYEOF
}

usage() {
  sed -n '1,/^set -euo pipefail/p' "$0" | sed 's/^# \?//'
}

case "${1:-}" in
  start)   shift; cmd_start "$@" ;;
  stop)    shift; cmd_stop "$@" ;;
  restart) shift; cmd_restart "$@" ;;
  status)  shift; cmd_status "$@" ;;
  logs)    shift; cmd_logs "$@" ;;
  doctor)  shift; cmd_doctor "$@" ;;
  -h|--help|help|"") usage; exit 0 ;;
  *) echo "::error:: unknown subcommand: $1" >&2; usage; exit 2 ;;
esac
