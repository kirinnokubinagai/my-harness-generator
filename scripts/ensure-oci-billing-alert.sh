#!/usr/bin/env bash
# ensure-oci-billing-alert.sh — idempotently provision the OCI billing guard.
#
#   bash ensure-oci-billing-alert.sh <root> [<alert-email>]
#
# Creates (idempotent — safe to re-run; everything is looked up by name):
#   1. OCI Budget "harness-billing-guard"  ($1, MONTHLY, target = tenancy)
#   2. Budget Alert Rule "harness-billing-alert"
#        type=ACTUAL, threshold=1 PERCENTAGE of $1 ≈ $0.01, recipients=<email>
#      → an email fires the moment OCI bills ANYTHING. This path lives
#        entirely in OCI and is the VM-independent backup.
#   3. (BILLING_ALERT_MODE = chat|both only) a dynamic-group + policy so the
#      VM's instance principal can `oci budgets budget get` — billing-check.sh
#      on the VM then posts to the existing notification webhook.
#
# HONEST LATENCY: OCI budget data updates on a ~24h cycle and the Usage API
# is officially unsupported on Always Free (non-metered) tenancies, so the
# budget actual-spend is the only viable signal and ~24h is the structural
# floor. There is no real-time OCI billing alert on Always Free.
#
# Reads  .my-harness/.oci-vm.env       (OCI_VM_INSTANCE_ID, OCI_VM_REGION)
#        .my-harness/.notification.env (BILLING_ALERT_MODE, BILLING_ALERT_EMAIL)
# Writes .my-harness/.oci-billing.env  (BILLING_BUDGET_OCID) chmod 600
#
# Exit 3 if no alert email (SKILL.md should AskUserQuestion then re-invoke).
# Exit 0 (noop) if BILLING_ALERT_MODE=off.

set -u
ROOT="${1:?root required}"
EMAIL_ARG="${2:-}"

NOTIF="$ROOT/.my-harness/.notification.env"
OCIVM="$ROOT/.my-harness/.oci-vm.env"
OUT="$ROOT/.my-harness/.oci-billing.env"
OCI_CONFIG="${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}"

BUDGET_NAME="harness-billing-guard"
ALERT_NAME="harness-billing-alert"
DG_NAME="harness-billing-poller-dg"
POLICY_NAME="harness-billing-poller-policy"

[ -f "$NOTIF" ] || { echo "::error:: $NOTIF missing — run Phase 1 first" >&2; exit 1; }
[ -f "$OCIVM" ] || { echo "::error:: $OCIVM missing — run ensure-oci-vm.sh first" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
. "$NOTIF"
# shellcheck disable=SC1090
. "$OCIVM"
set +a

: "${BILLING_ALERT_MODE:=off}"
if [ "$BILLING_ALERT_MODE" = "off" ]; then
  echo "[billing] BILLING_ALERT_MODE=off — nothing to do"
  exit 0
fi

EMAIL="${EMAIL_ARG:-${BILLING_ALERT_EMAIL:-}}"
if [ -z "$EMAIL" ]; then
  echo "::error:: billing alert email not provided." >&2
  echo "  The OCI Budget email alert is the VM-independent backup and is ALWAYS required" >&2
  echo "  (even for chat-only mode — it is the safety net if the VM dies silently)." >&2
  echo "  Re-invoke: bash scripts/ensure-oci-billing-alert.sh \"$ROOT\" <email>" >&2
  exit 3
fi
if ! printf '%s' "$EMAIL" | grep -qE '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; then
  echo "::error:: '$EMAIL' doesn't look like an email address" >&2
  exit 2
fi

command -v oci >/dev/null 2>&1 || {
  echo "::error:: 'oci' CLI not on PATH." >&2
  echo "  Enter the dev shell:  nix develop   (or: nix shell nixpkgs#oci-cli)" >&2
  exit 1
}

# Tenancy OCID from ~/.oci/config [DEFAULT] — same extraction as ensure-oci-vm.sh.
TENANCY_OCID="$(awk -F= '/^\[/{p=$0} p=="[DEFAULT]" && $1 ~ /^tenancy[[:space:]]*$/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$OCI_CONFIG")"
[ -n "$TENANCY_OCID" ] || { echo "::error:: could not read 'tenancy' from $OCI_CONFIG [DEFAULT]" >&2; exit 1; }

REGION="${OCI_VM_REGION:?OCI_VM_REGION missing from .oci-vm.env}"
ocireg=(--region "$REGION")

echo "[billing] tenancy=$TENANCY_OCID region=$REGION mode=$BILLING_ALERT_MODE"

# ── 1. Budget (idempotent by display-name) ───────────────────────────────
BUDGET_OCID="$(oci budgets budget list \
  --compartment-id "$TENANCY_OCID" "${ocireg[@]}" \
  --query "data[?\"display-name\"=='$BUDGET_NAME'].id | [0]" \
  --raw-output 2>/dev/null || true)"
if [ -z "$BUDGET_OCID" ] || [ "$BUDGET_OCID" = "null" ]; then
  echo "[billing] creating budget '$BUDGET_NAME' (\$1 MONTHLY, target=tenancy)..."
  BUDGET_OCID="$(oci budgets budget create \
    --compartment-id "$TENANCY_OCID" "${ocireg[@]}" \
    --amount 1 --reset-period MONTHLY \
    --target-type COMPARTMENT --targets "[\"$TENANCY_OCID\"]" \
    --display-name "$BUDGET_NAME" \
    --description "harness: alert on ANY charge beyond Always Free" \
    --query 'data.id' --raw-output)"
else
  echo "[billing] budget already exists: $BUDGET_OCID"
fi
if [ -z "$BUDGET_OCID" ] || [ "$BUDGET_OCID" = "null" ]; then
  echo "::error:: failed to obtain budget OCID" >&2
  exit 1
fi

# ── 2. Alert Rule (idempotent by display-name) ───────────────────────────
RULE_OCID="$(oci budgets alert-rule list \
  --budget-id "$BUDGET_OCID" "${ocireg[@]}" \
  --query "data[?\"display-name\"=='$ALERT_NAME'].id | [0]" \
  --raw-output 2>/dev/null || true)"
if [ -z "$RULE_OCID" ] || [ "$RULE_OCID" = "null" ]; then
  echo "[billing] creating alert rule '$ALERT_NAME' (ACTUAL 1% of \$1 ≈ \$0.01 → $EMAIL)..."
  oci budgets alert-rule create \
    --budget-id "$BUDGET_OCID" "${ocireg[@]}" \
    --type ACTUAL --threshold 1 --threshold-type PERCENTAGE \
    --recipients "$EMAIL" \
    --display-name "$ALERT_NAME" \
    --message "OCI billing: a charge beyond Always Free was detected. Check the OCI console." \
    >/dev/null
else
  echo "[billing] alert rule already exists: $RULE_OCID (recipients left unchanged)"
fi

# ── 3. chat/both: instance principal so the VM can read the budget ───────
if [ "$BILLING_ALERT_MODE" = "chat" ] || [ "$BILLING_ALERT_MODE" = "both" ]; then
  INST="${OCI_VM_INSTANCE_ID:?OCI_VM_INSTANCE_ID missing from .oci-vm.env}"

  DG_OCID="$(oci iam dynamic-group list \
    --query "data[?name=='$DG_NAME'].id | [0]" --raw-output 2>/dev/null || true)"
  if [ -z "$DG_OCID" ] || [ "$DG_OCID" = "null" ]; then
    echo "[billing] creating dynamic-group '$DG_NAME' (instance.id = the VM)..."
    oci iam dynamic-group create \
      --name "$DG_NAME" \
      --description "harness billing poller VM" \
      --matching-rule "instance.id = '$INST'" >/dev/null
  else
    echo "[billing] dynamic-group already exists: $DG_OCID"
  fi

  POL_OCID="$(oci iam policy list \
    --compartment-id "$TENANCY_OCID" \
    --query "data[?name=='$POLICY_NAME'].id | [0]" --raw-output 2>/dev/null || true)"
  if [ -z "$POL_OCID" ] || [ "$POL_OCID" = "null" ]; then
    echo "[billing] creating policy '$POLICY_NAME' (read budgets in tenancy)..."
    oci iam policy create \
      --compartment-id "$TENANCY_OCID" \
      --name "$POLICY_NAME" \
      --description "harness billing poller: read budgets" \
      --statements "[\"allow dynamic-group $DG_NAME to read budgets in tenancy\"]" >/dev/null
  else
    echo "[billing] policy already exists: $POL_OCID"
  fi
fi

# ── 4. persist budget OCID for setup-oci-vm-nixos.sh ─────────────────────
mkdir -p "$ROOT/.my-harness"
{ grep -v '^BILLING_BUDGET_OCID=' "$OUT" 2>/dev/null || true; echo "BILLING_BUDGET_OCID=$BUDGET_OCID"; } > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
chmod 600 "$OUT"

echo "[billing] done. BILLING_BUDGET_OCID=$BUDGET_OCID → $OUT"
echo "  email backup → $EMAIL (fires within ~24h of any charge; VM-independent)"
if [ "$BILLING_ALERT_MODE" != "email" ]; then
  echo "  chat alerts  → VM billing-check.timer via ${NOTIFICATION_SERVICE:-discord} webhook (~24h OCI lag)"
fi
