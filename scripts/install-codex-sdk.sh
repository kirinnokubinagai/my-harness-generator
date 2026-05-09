#!/usr/bin/env bash
# Summary: Bootstrap the dedicated Python venv that codex-app-server-call.py
#          needs. Installs `codex-app-server-sdk` (the official Python SDK
#          for talking to `codex app-server` over WebSocket / stdio) plus
#          its transitive deps (websockets, pydantic, etc.) into a venv
#          at $HOME/.codex/my-harness-venv. The harness uses this venv
#          via $MY_HARNESS_CODEX_PY (default: that venv's python).
#
#          Why a venv? Homebrew's Python 3.12+ is PEP 668 "externally
#          managed" — global pip installs are blocked. A dedicated venv
#          keeps the harness off the user's system Python and out of any
#          project-local environment.
#
#          PREFERRED: if you have Nix, run `nix develop` (or `direnv allow`)
#          at the repo root instead. The flake provides codex + rtk + Python
#          + the SDK pre-built and pinned via flake.lock — no venv needed.
#          This script is the venv-based fallback for users who can't or
#          don't want to install Nix.
#
# Usage:
#   bash scripts/install-codex-sdk.sh            # install / upgrade
#   bash scripts/install-codex-sdk.sh --check    # just verify, no install
#   bash scripts/install-codex-sdk.sh --remove   # delete the venv

set -euo pipefail

VENV_DIR="${MY_HARNESS_CODEX_VENV:-$HOME/.codex/my-harness-venv}"
PYTHON_BIN="${MY_HARNESS_BOOTSTRAP_PYTHON:-python3}"
PACKAGE="codex-app-server-sdk"

case "${1:-}" in
  --check) MODE=check ;;
  --remove) MODE=remove ;;
  ""|--install) MODE=install ;;
  --help|-h) sed -n '1,/^set -euo pipefail/p' "$0" | sed 's/^# \?//'; exit 0 ;;
  *) echo "::error:: unknown flag: $1" >&2; exit 2 ;;
esac

if [ "$MODE" = "remove" ]; then
  if [ -d "$VENV_DIR" ]; then
    rm -rf "$VENV_DIR"
    echo "[install-codex-sdk] removed $VENV_DIR"
  else
    echo "[install-codex-sdk] $VENV_DIR not present"
  fi
  exit 0
fi

if [ "$MODE" = "check" ]; then
  if [ ! -x "$VENV_DIR/bin/python" ]; then
    echo "::error:: venv missing at $VENV_DIR" >&2
    exit 1
  fi
  if ! "$VENV_DIR/bin/python" -c "import codex_app_server_sdk" >/dev/null 2>&1; then
    echo "::error:: codex_app_server_sdk not importable from $VENV_DIR" >&2
    exit 1
  fi
  echo "[install-codex-sdk] OK ($VENV_DIR)"
  "$VENV_DIR/bin/python" -c "import codex_app_server_sdk; print('  module:', codex_app_server_sdk.__file__)"
  exit 0
fi

# install / upgrade
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "::error:: $PYTHON_BIN not found in PATH (override with \$MY_HARNESS_BOOTSTRAP_PYTHON)" >&2
  exit 127
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
  echo "[install-codex-sdk] creating venv at $VENV_DIR"
  mkdir -p "$(dirname "$VENV_DIR")"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

echo "[install-codex-sdk] upgrading pip"
"$VENV_DIR/bin/pip" install --quiet --upgrade pip

echo "[install-codex-sdk] installing $PACKAGE"
"$VENV_DIR/bin/pip" install --quiet --upgrade "$PACKAGE"

echo
echo "[install-codex-sdk] verifying"
"$VENV_DIR/bin/python" - << 'PYEOF'
import codex_app_server_sdk as sdk
mods = ["CodexClient", "ThreadConfig", "ChatResult"]
missing = [m for m in mods if not hasattr(sdk, m)]
if missing:
    raise SystemExit(f"missing exports: {missing}")
print(f"  package OK ({sdk.__file__})")
PYEOF

echo
echo "[install-codex-sdk] done."
echo "  codex-ask.sh / codex-daemon.sh will pick up the venv automatically."
echo "  Override the path with \$MY_HARNESS_CODEX_PY if needed."
