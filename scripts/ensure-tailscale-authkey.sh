#!/usr/bin/env bash
# ensure-tailscale-authkey.sh — capture the Tailscale auth key the user
# generated in the Tailscale admin console (https://login.tailscale.com/
# admin/settings/keys). For a permanent headless OCI VM use a key that is:
#   - Tagged (e.g. tag:oci-harness) — ACLs apply post-provision
#   - Reusable: NO (one VM, one key; rotate by re-running this)
#   - Ephemeral: NO (the VM is long-lived; ephemeral would deregister it
#     every time it goes offline)
#   - Expiry: 90 days is fine; the node stays up, only the KEY expires.
#     Re-run this script + setup-oci-vm-nixos.sh to rotate.
#
# Saved to <root>/.my-harness/.tailscale-authkey (chmod 600), scp'd to
# /home/opc/.tailscale-authkey by setup-oci-vm-nixos.sh.
#
# Usage:
#   bash ensure-tailscale-authkey.sh <root> [<authkey>]
#
# Exit 3 if no key provided (SKILL.md should AskUserQuestion then re-invoke).

set -u
ROOT="${1:?root required}"
KEY="${2:-}"
OUT="$ROOT/.my-harness/.tailscale-authkey"

if [ -z "$KEY" ]; then
  echo "::error:: no Tailscale auth key provided." >&2
  echo "  Generate one at https://login.tailscale.com/admin/settings/keys" >&2
  echo "  Recommended: Reusable=OFF, Ephemeral=OFF, Tagged (tag:oci-harness), 90-day expiry." >&2
  echo "  Then re-invoke: bash ensure-tailscale-authkey.sh <root> <authkey>" >&2
  exit 3
fi

# Tailscale auth keys look like: tskey-auth-<keyID>-<secret>
if ! printf '%s' "$KEY" | grep -qE '^tskey-auth-[A-Za-z0-9]+-[A-Za-z0-9]+$'; then
  echo "::error:: that doesn't look like a Tailscale auth key (expected tskey-auth-...)." >&2
  exit 2
fi

mkdir -p "$ROOT/.my-harness"
printf '%s' "$KEY" > "$OUT"
chmod 600 "$OUT"
echo "[tailscale-authkey] saved to $OUT (chmod 600)"
echo "  This is scp'd to /home/opc/.tailscale-authkey by setup-oci-vm-nixos.sh."
echo "  When it expires (~90d), re-run this + setup-oci-vm-nixos.sh to rotate."
