#!/usr/bin/env bash
# ensure-oci-vm.sh — idempotent provisioner for an Always-Free Oracle
# Cloud Ampere A1 VM that will host the daily-progress bot.
#
# Persists state to <root>/.my-harness/.oci-vm.env:
#   OCI_VM_NAME=<vm-name>
#   OCI_VM_REGION=<region>
#   OCI_VM_INSTANCE_ID=<ocid>
#   OCI_VM_PUBLIC_IP=<ip>
#   OCI_VM_SSH_KEY=<~/.ssh/...>
#
# If that file already exists AND the recorded instance is still
# RUNNING, the script is a no-op (idempotent re-run).
#
# Usage:
#   bash ensure-oci-vm.sh <root> <vm-name> <region> <ssh-key-filename>
#
# Example:
#   bash ensure-oci-vm.sh /path/to/proj kirin ap-osaka-1 kirin_oracle_cloud.key
#
# Prerequisites enforced by this script:
#   1. .my-harness/.notification.env exists with NOTIFICATION_SERVICE,
#      NOTIFICATION_WEBHOOK_URL, GH_TOKEN (run the two ensure-*.sh
#      scripts first).
#   2. ~/.oci/config is configured (see Oracle docs link below).
#   3. `oci` CLI is on PATH (enter `nix develop` first).

set -u

ROOT="${1:?root required (path to project root containing .my-harness/)}"
VM_NAME="${2:?vm-name required}"
REGION="${3:?region required (e.g. ap-osaka-1)}"
SSH_KEY_FILENAME="${4:?ssh-key-filename required (e.g. kirin_oracle_cloud.key)}"

trap 'rc=$?; if [ $rc -ne 0 ]; then echo "::error:: ensure-oci-vm.sh failed at line $LINENO (exit $rc)" >&2; fi' EXIT

# -----------------------------------------------------------------------------
# Step 2: load .notification.env and confirm all three vars are present.
# -----------------------------------------------------------------------------
NOTIF_FILE="$ROOT/.my-harness/.notification.env"
if [ ! -f "$NOTIF_FILE" ]; then
  echo "::error:: $NOTIF_FILE not found." >&2
  echo "  Run scripts/ensure-notification-webhook.sh and scripts/ensure-github-pat.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
. "$NOTIF_FILE"
set +a

missing=()
[ -n "${NOTIFICATION_SERVICE:-}" ] || missing+=("NOTIFICATION_SERVICE")
[ -n "${NOTIFICATION_WEBHOOK_URL:-}" ] || missing+=("NOTIFICATION_WEBHOOK_URL")
[ -n "${GH_TOKEN:-}" ] || missing+=("GH_TOKEN")
if [ "${#missing[@]}" -gt 0 ]; then
  echo "::error:: missing in $NOTIF_FILE: ${missing[*]}" >&2
  echo "  Run scripts/ensure-notification-webhook.sh <root> <service> <url>" >&2
  echo "  Run scripts/ensure-github-pat.sh <root> <pat>" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Step 3: SSH key — generate if absent.
# -----------------------------------------------------------------------------
SSH_KEY_PATH="$HOME/.ssh/$SSH_KEY_FILENAME"
SSH_KEY_PUB="$SSH_KEY_PATH.pub"

if [ ! -f "$SSH_KEY_PATH" ]; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  echo "[oci-vm] generating SSH key at $SSH_KEY_PATH"
  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "oci-$VM_NAME" >/dev/null
  chmod 600 "$SSH_KEY_PATH"
  chmod 644 "$SSH_KEY_PUB"
  echo "[oci-vm] created public key: $SSH_KEY_PUB"
else
  echo "[oci-vm] reusing existing SSH key: $SSH_KEY_PATH"
fi

# -----------------------------------------------------------------------------
# Step 4: confirm ~/.oci/config exists.
# -----------------------------------------------------------------------------
OCI_CONFIG="$HOME/.oci/config"
if [ ! -f "$OCI_CONFIG" ]; then
  cat >&2 <<'EOF'
::error:: ~/.oci/config not found.

To set up OCI CLI authentication:

  1. Sign in to https://cloud.oracle.com
  2. Profile menu (top-right) → User settings → API keys → Add API Key
       - Generate a new key pair (download both files)
  3. Note these values from the "Configuration File Preview":
       - user OCID         (ocid1.user.oc1..xxxxx)
       - fingerprint       (xx:xx:xx:...)
       - tenancy OCID      (ocid1.tenancy.oc1..xxxxx)
       - region            (e.g. ap-osaka-1)
       - key_file          (path where you saved the private API key)
  4. Run:    oci setup config
     OR write ~/.oci/config manually with the values above.

Full docs:
  https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm
EOF
  exit 1
fi

# -----------------------------------------------------------------------------
# Step 5: oci CLI on PATH?
# -----------------------------------------------------------------------------
if ! command -v oci >/dev/null 2>&1; then
  echo "::error:: 'oci' CLI not on PATH." >&2
  echo "  Enter the dev shell first:  nix develop" >&2
  echo "  (or install ad-hoc:         nix shell nixpkgs#oci-cli)" >&2
  exit 1
fi

# Extract the tenancy OCID from ~/.oci/config (DEFAULT profile).
TENANCY_OCID="$(awk -F= '/^\[/{p=$0} p=="[DEFAULT]" && $1 ~ /^tenancy[[:space:]]*$/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$OCI_CONFIG")"
if [ -z "$TENANCY_OCID" ]; then
  echo "::error:: could not read 'tenancy' from $OCI_CONFIG [DEFAULT] section" >&2
  exit 1
fi
echo "[oci-vm] tenancy: $TENANCY_OCID"
echo "[oci-vm] region:  $REGION"

# -----------------------------------------------------------------------------
# Step 12 (early-exit): idempotence — if .oci-vm.env says RUNNING, skip.
# -----------------------------------------------------------------------------
OUT_ENV="$ROOT/.my-harness/.oci-vm.env"
if [ -f "$OUT_ENV" ]; then
  # shellcheck disable=SC1090
  (
    set -a
    . "$OUT_ENV"
    set +a
    if [ -n "${OCI_VM_INSTANCE_ID:-}" ]; then
      state="$(oci compute instance get \
                 --instance-id "$OCI_VM_INSTANCE_ID" \
                 --region "$REGION" \
                 --query 'data."lifecycle-state"' \
                 --raw-output 2>/dev/null || true)"
      if [ "$state" = "RUNNING" ]; then
        echo "[oci-vm] already provisioned and RUNNING — skipping."
        echo "[oci-vm] ready: ssh -i $OCI_VM_SSH_KEY opc@$OCI_VM_PUBLIC_IP"
        exit 0
      fi
      echo "[oci-vm] prior instance state is '$state' — re-provisioning."
    fi
  ) && exit 0 || true
fi

# -----------------------------------------------------------------------------
# Step 6: list availability domains in the region.
# -----------------------------------------------------------------------------
echo "[oci-vm] discovering availability domains..."
ADS_JSON="$(oci iam availability-domain list \
              --compartment-id "$TENANCY_OCID" \
              --region "$REGION" \
              --all \
              --query 'data[*].name' \
              --raw-output 2>/dev/null)" || {
  echo "::error:: failed to list ADs in $REGION." >&2
  exit 2
}

# Normalize JSON array to a bash array, one AD per line.
ADS=()
while IFS= read -r line; do
  line="$(echo "$line" | sed -e 's/^[[:space:]]*"//' -e 's/",*$//' -e 's/^\[//' -e 's/\]$//')"
  [ -n "$line" ] && ADS+=("$line")
done < <(printf '%s\n' "$ADS_JSON" | tr ',' '\n')

if [ "${#ADS[@]}" -eq 0 ]; then
  echo "::error:: no ADs returned for region $REGION" >&2
  exit 2
fi
echo "[oci-vm] availability domains: ${ADS[*]}"

# -----------------------------------------------------------------------------
# Step 7: latest Oracle Linux 9 ARM image.
# -----------------------------------------------------------------------------
echo "[oci-vm] discovering latest Oracle Linux 9 ARM image..."
IMAGE_ID="$(oci compute image list \
              --compartment-id "$TENANCY_OCID" \
              --region "$REGION" \
              --shape "VM.Standard.A1.Flex" \
              --operating-system "Oracle Linux" \
              --operating-system-version "9" \
              --sort-by TIMECREATED \
              --sort-order DESC \
              --limit 1 \
              --query 'data[0].id' \
              --raw-output 2>/dev/null)" || {
  echo "::error:: failed to query Oracle Linux 9 ARM image" >&2
  exit 2
}

if [ -z "$IMAGE_ID" ] || [ "$IMAGE_ID" = "null" ]; then
  echo "::error:: no Oracle Linux 9 ARM image returned for $REGION" >&2
  exit 2
fi
echo "[oci-vm] image: $IMAGE_ID"

# -----------------------------------------------------------------------------
# Step 8: discover (or create) default VCN + subnet.
# -----------------------------------------------------------------------------
echo "[oci-vm] discovering VCN/subnet..."

VCN_ID="$(oci network vcn list \
            --compartment-id "$TENANCY_OCID" \
            --region "$REGION" \
            --all \
            --query 'data[0].id' \
            --raw-output 2>/dev/null || true)"

if [ -z "$VCN_ID" ] || [ "$VCN_ID" = "null" ]; then
  echo "[oci-vm] no VCN found — creating one..."
  VCN_ID="$(oci network vcn create \
              --compartment-id "$TENANCY_OCID" \
              --region "$REGION" \
              --cidr-block "10.0.0.0/16" \
              --display-name "${VM_NAME}-vcn" \
              --dns-label "harness$(date +%s | tail -c5)" \
              --wait-for-state AVAILABLE \
              --query 'data.id' \
              --raw-output 2>/dev/null)" || {
    echo "::error:: failed to create VCN — fix manually in OCI Console and re-run." >&2
    exit 2
  }
fi
echo "[oci-vm] VCN: $VCN_ID"

# Look for an existing public subnet in this VCN.
SUBNET_ID="$(oci network subnet list \
               --compartment-id "$TENANCY_OCID" \
               --region "$REGION" \
               --vcn-id "$VCN_ID" \
               --all \
               --query 'data[?"prohibit-public-ip-on-vnic"==`false`] | [0].id' \
               --raw-output 2>/dev/null || true)"

if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "null" ]; then
  echo "[oci-vm] no public subnet found in VCN — provisioning network stack..."

  # ---- 1. Internet Gateway -------------------------------------------------
  IGW_ID="$(oci network internet-gateway list \
              --compartment-id "$TENANCY_OCID" \
              --region "$REGION" \
              --vcn-id "$VCN_ID" \
              --all \
              --query 'data[0].id' \
              --raw-output 2>/dev/null || true)"

  if [ -z "$IGW_ID" ] || [ "$IGW_ID" = "null" ]; then
    echo "[oci-vm] creating internet gateway..."
    IGW_ID="$(oci network internet-gateway create \
                --compartment-id "$TENANCY_OCID" \
                --region "$REGION" \
                --vcn-id "$VCN_ID" \
                --is-enabled true \
                --display-name "${VM_NAME}-igw" \
                --wait-for-state AVAILABLE \
                --query 'data.id' \
                --raw-output 2>/dev/null)" || {
      echo "::error:: failed to create internet gateway." >&2
      exit 2
    }
  fi
  echo "[oci-vm] IGW: $IGW_ID"

  # ---- 2. Route table: ensure 0.0.0.0/0 -> IGW rule on default RT ----------
  RT_ID="$(oci network vcn get \
             --vcn-id "$VCN_ID" \
             --region "$REGION" \
             --query 'data."default-route-table-id"' \
             --raw-output 2>/dev/null)" || {
    echo "::error:: failed to get default route table id." >&2
    exit 2
  }
  echo "[oci-vm] route table: $RT_ID"

  RT_HAS_DEFAULT="$(oci network route-table get \
                      --rt-id "$RT_ID" \
                      --region "$REGION" \
                      --query 'data."route-rules"[?"destination"==`0.0.0.0/0`] | [0]."network-entity-id"' \
                      --raw-output 2>/dev/null || true)"

  if [ -z "$RT_HAS_DEFAULT" ] || [ "$RT_HAS_DEFAULT" = "null" ]; then
    echo "[oci-vm] adding 0.0.0.0/0 -> IGW route..."
    oci network route-table update \
      --rt-id "$RT_ID" \
      --region "$REGION" \
      --route-rules "[{\"cidrBlock\":\"0.0.0.0/0\",\"networkEntityId\":\"$IGW_ID\"}]" \
      --force >/dev/null 2>&1 || {
      echo "::error:: failed to update route table with default route." >&2
      exit 2
    }
  else
    echo "[oci-vm] default route already present — skipping."
  fi

  # ---- 3. Security list: open SSH (port 22) from 0.0.0.0/0 -----------------
  SL_ID="$(oci network vcn get \
             --vcn-id "$VCN_ID" \
             --region "$REGION" \
             --query 'data."default-security-list-id"' \
             --raw-output 2>/dev/null)" || {
    echo "::error:: failed to get default security list id." >&2
    exit 2
  }
  echo "[oci-vm] security list: $SL_ID"

  SL_HAS_SSH="$(oci network security-list get \
                  --security-list-id "$SL_ID" \
                  --region "$REGION" \
                  --query 'data."ingress-security-rules"[?"tcp-options"."destination-port-range".min==`22` && "tcp-options"."destination-port-range".max==`22`] | [0].source' \
                  --raw-output 2>/dev/null || true)"

  # OCI_SSH_SOURCE_CIDR — restrict SSH ingress to a specific IP/CIDR instead of
  # the default 0.0.0.0/0. Set to e.g. <my-ip>/32 for maximum restriction.
  # setup-oci-vm-nixos.sh closes port 22 entirely post-Tailscale-verification when
  # TAILSCALE_ENABLED=yes, so this CIDR only matters for non-Tailscale deployments.
  : "${OCI_SSH_SOURCE_CIDR:=0.0.0.0/0}"

  if [ -z "$SL_HAS_SSH" ] || [ "$SL_HAS_SSH" = "null" ]; then
    echo "[oci-vm] opening SSH ingress (port 22) from $OCI_SSH_SOURCE_CIDR..."
    oci network security-list update \
      --security-list-id "$SL_ID" \
      --region "$REGION" \
      --ingress-security-rules "[{\"source\":\"$OCI_SSH_SOURCE_CIDR\",\"protocol\":\"6\",\"tcpOptions\":{\"destinationPortRange\":{\"min\":22,\"max\":22}},\"isStateless\":false}]" \
      --force >/dev/null 2>&1 || {
      echo "::error:: failed to update security list with SSH ingress." >&2
      exit 2
    }
  else
    echo "[oci-vm] SSH ingress rule already present — skipping."
  fi

  # UDP 41641 — Tailscale direct P2P. Harmless when Tailscale is OFF (nothing
  # listens on 41641). Required for optimal Tailscale performance when ON;
  # Tailscale falls back to DERP (TCP/443) if this UDP port is blocked.
  SL_HAS_TAILSCALE_UDP="$(oci network security-list get \
                            --security-list-id "$SL_ID" \
                            --region "$REGION" \
                            --query 'data."ingress-security-rules"[?"protocol"==`17` && "udpOptions"."destinationPortRange".min==`41641`] | [0].source' \
                            --raw-output 2>/dev/null || true)"

  if [ -z "$SL_HAS_TAILSCALE_UDP" ] || [ "$SL_HAS_TAILSCALE_UDP" = "null" ]; then
    echo "[oci-vm] opening Tailscale UDP 41641 ingress from 0.0.0.0/0..."
    # Fetch current ingress rules and append the UDP 41641 rule.
    _CURRENT_INGRESS="$(oci network security-list get \
      --security-list-id "$SL_ID" \
      --region "$REGION" \
      --query 'data."ingress-security-rules"' \
      --raw-output 2>/dev/null || true)"
    _NEW_INGRESS="$(printf '%s' "$_CURRENT_INGRESS" | python3 -c "
import json, sys
rules = json.load(sys.stdin)
rules.append({
  'source': '0.0.0.0/0',
  'protocol': '17',
  'udpOptions': {'destinationPortRange': {'min': 41641, 'max': 41641}},
  'isStateless': False
})
print(json.dumps(rules))
" 2>/dev/null || true)"
    if [ -n "$_NEW_INGRESS" ]; then
      oci network security-list update \
        --security-list-id "$SL_ID" \
        --region "$REGION" \
        --ingress-security-rules "$_NEW_INGRESS" \
        --force >/dev/null 2>&1 || {
        echo "::warning:: failed to add Tailscale UDP 41641 ingress — add manually if using Tailscale." >&2
      }
    fi
  else
    echo "[oci-vm] Tailscale UDP 41641 ingress rule already present — skipping."
  fi

  # ---- 4. Public subnet ----------------------------------------------------
  echo "[oci-vm] creating public subnet (10.0.1.0/24)..."
  SUBNET_ID="$(oci network subnet create \
                 --compartment-id "$TENANCY_OCID" \
                 --region "$REGION" \
                 --vcn-id "$VCN_ID" \
                 --cidr-block "10.0.1.0/24" \
                 --display-name "${VM_NAME}-subnet" \
                 --prohibit-public-ip-on-vnic false \
                 --wait-for-state AVAILABLE \
                 --query 'data.id' \
                 --raw-output 2>/dev/null)" || {
    echo "::error:: failed to create subnet." >&2
    exit 2
  }
fi
echo "[oci-vm] subnet: $SUBNET_ID"

# -----------------------------------------------------------------------------
# Step 9 + 6 retry: try each AD; retry on "Out of Host Capacity".
# -----------------------------------------------------------------------------
launch_in_ad() {
  local ad="$1"
  echo "[oci-vm] launching $VM_NAME in AD '$ad'..." >&2
  # NOTE: stderr is kept on the pipeline so callers can grep for
  # "Out of Host Capacity"; stdout carries the OCID on success.
  oci compute instance launch \
    --availability-domain "$ad" \
    --compartment-id "$TENANCY_OCID" \
    --shape "VM.Standard.A1.Flex" \
    --shape-config '{"ocpus":4,"memoryInGBs":24}' \
    --boot-volume-size-in-gbs 200 \
    --display-name "$VM_NAME" \
    --image-id "$IMAGE_ID" \
    --subnet-id "$SUBNET_ID" \
    --ssh-authorized-keys-file "$SSH_KEY_PUB" \
    --wait-for-state RUNNING \
    --region "$REGION" \
    --query 'data.id' \
    --raw-output 2>&1
}

INSTANCE_ID=""
TRIES=0
MAX_TRIES=3
for ad in "${ADS[@]}"; do
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -gt "$MAX_TRIES" ]; then
    break
  fi
  out="$(launch_in_ad "$ad" || true)"
  # Strip OCI CLI pagination WARNINGs so the OCID match is robust.
  ocid_line="$(printf '%s\n' "$out" | grep -v '^WARNING:' | grep -E '^ocid1\.instance' | head -n1 || true)"
  if [ -n "$ocid_line" ]; then
    INSTANCE_ID="$ocid_line"
    echo "[oci-vm] launched: $INSTANCE_ID"
    break
  fi
  if echo "$out" | grep -qi "Out of Host Capacity"; then
    echo "[oci-vm] AD '$ad' is out of A1 capacity — trying next AD..." >&2
    continue
  fi
  echo "::error:: launch in AD '$ad' failed:" >&2
  echo "$out" >&2
done

if [ -z "$INSTANCE_ID" ]; then
  echo "::error:: could not launch in any of ${#ADS[@]} ADs (tried $TRIES)." >&2
  echo "  Always-Free A1 capacity is region-wide scarce; try again later or pick another region." >&2
  exit 2
fi

# -----------------------------------------------------------------------------
# Step 10: get public IP.
# -----------------------------------------------------------------------------
echo "[oci-vm] resolving public IP..."
PUBLIC_IP="$(oci compute instance list-vnics \
               --instance-id "$INSTANCE_ID" \
               --region "$REGION" \
               --all \
               --query 'data[0]."public-ip"' \
               --raw-output 2>/dev/null)" || {
  echo "::error:: failed to fetch public IP." >&2
  exit 2
}

if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "null" ]; then
  echo "::error:: instance launched but no public IP attached." >&2
  echo "  Check that the subnet allows public IPs and that the VNIC was assigned one." >&2
  exit 2
fi

# -----------------------------------------------------------------------------
# Step 11: persist .oci-vm.env.
# -----------------------------------------------------------------------------
{
  echo "# Auto-written by scripts/ensure-oci-vm.sh — do not edit by hand."
  echo "# Re-run /my-harness-init or scripts/ensure-oci-vm.sh to refresh."
  echo "OCI_VM_NAME=$VM_NAME"
  echo "OCI_VM_REGION=$REGION"
  echo "OCI_VM_INSTANCE_ID=$INSTANCE_ID"
  echo "OCI_VM_PUBLIC_IP=$PUBLIC_IP"
  echo "OCI_VM_SSH_KEY=$SSH_KEY_PATH"
} > "$OUT_ENV"
chmod 600 "$OUT_ENV"

# -----------------------------------------------------------------------------
# Step 13: success summary.
# -----------------------------------------------------------------------------
echo "[oci-vm] ready: ssh -i $SSH_KEY_PATH opc@$PUBLIC_IP"
echo "[oci-vm] state saved to $OUT_ENV"
