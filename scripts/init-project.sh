#!/usr/bin/env bash
# Summary: Backward-compatibility redirect. The actual implementation is bootstrap.sh.
#          New users should call bootstrap.sh directly.
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "[init-project] This script is deprecated. Forwarding to bootstrap.sh."
exec bash "$HARNESS_DIR/scripts/bootstrap.sh" "$@"
