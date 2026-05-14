#!/usr/bin/env bash
# ensure-codex-auth.sh — capture / refresh the local Codex CLI OAuth
# credentials so setup-oci-vm.sh can copy them to the OCI VM.
#
# The Codex CLI (npm i -g @openai/codex) stores its OAuth state at
# ~/.codex/auth.json after `codex login`. That file contains access
# token (~10 day life), refresh token (~3 month life), and id token.
# We snapshot it to .my-harness/.codex-auth.json (chmod 600), and
# setup-oci-vm.sh scps it to the VM's ~/.codex/auth.json so the
# VM-side codex CLI can call ChatGPT subscription endpoints without
# any browser interaction.
#
# When the refresh token eventually expires (~3 months), the VM's
# next `codex exec` call will start failing — the fix is to re-run
# `codex login` on this Mac and re-run this script + setup-oci-vm.sh
# (or just setup-oci-vm.sh, which re-invokes this).
#
# Usage:
#   bash ensure-codex-auth.sh <root>

set -u

ROOT="${1:?root required (project root containing .my-harness/)}"
SRC="$HOME/.codex/auth.json"
DEST="$ROOT/.my-harness/.codex-auth.json"

if [ ! -f "$SRC" ]; then
  echo "::error:: Codex OAuth credentials not found at $SRC" >&2
  echo "  Run \`codex login\` on this Mac first." >&2
  echo "  A browser will open — sign in with the ChatGPT Plus/Pro account you want the VM to use." >&2
  echo "  Then re-run this script (or simply re-run setup-oci-vm.sh, which calls this automatically)." >&2
  exit 3
fi

mkdir -p "$ROOT/.my-harness"
cp "$SRC" "$DEST"
chmod 600 "$DEST"

echo "[codex-auth] saved Codex OAuth credentials to $DEST (chmod 600)"
echo "  Source:      $SRC"
echo "  Destination: $DEST"
echo "  Lifetime:    refresh token typically ~3 months; re-run \`codex login\` + this script when daily-progress starts failing with auth errors."
