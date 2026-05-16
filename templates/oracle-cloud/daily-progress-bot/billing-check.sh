#!/usr/bin/env bash
# billing-check.sh — OCI billing guard (runs on the VM via the
# billing-check.timer systemd unit; see nixos/services/billing-check.nix).
#
# Reads the OCI Budget's actual-spend through Instance Principal auth. If OCI
# reports ANY charge (> 0 — i.e. Always Free has been exceeded), it posts a
# single alert to the existing notification webhook via post-notification.sh
# (the same discord/slack/teams webhook the daily-progress bot uses).
#
# De-dupes per calendar month: you get ONE alert when a charge first appears,
# not one every single day for the rest of the month.
#
# LATENCY (honest): OCI budget data updates on a ~24h cycle. This script
# cannot detect a charge faster than OCI itself surfaces it — ~24h is OCI's
# structural floor, not a bug here. The OCI Budget *email* alert (created by
# ensure-oci-billing-alert.sh, living entirely in OCI) is the independent
# backup if this script or the VM ever fails silently.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/post-notification.sh"

: "${BILLING_BUDGET_OCID:=}"
if [ -z "$BILLING_BUDGET_OCID" ]; then
  echo "::error:: BILLING_BUDGET_OCID unset (setup-oci-vm-nixos.sh writes it to .env)" >&2
  exit 1
fi

STATE_DIR="$HERE/state"
mkdir -p "$STATE_DIR"
MONTH="$(date -u +%Y-%m)"
SENTINEL="$STATE_DIR/billing-alerted-$MONTH"

# Instance Principal is set via Environment=OCI_CLI_AUTH=instance_principal
# in the systemd unit, so no ~/.oci/config is needed on the VM.
SPEND="$(oci budgets budget get \
           --budget-id "$BILLING_BUDGET_OCID" \
           --query 'data."actual-spend"' \
           --raw-output 2>/dev/null || echo "")"

case "$SPEND" in
  ''|null|None)
    echo "[billing-check] actual-spend not available yet (OCI ~24h lag) — no action"
    exit 0
    ;;
esac

# Any spend strictly greater than zero means Always Free was exceeded.
EXCEEDED="$(echo "$SPEND > 0" | bc -l 2>/dev/null || echo 0)"

if [ "$EXCEEDED" = "1" ]; then
  if [ -e "$SENTINEL" ]; then
    echo "[billing-check] already alerted for $MONTH (spend=$SPEND) — skip"
    exit 0
  fi
  # color 15158332 = 0xE74C3C (red) for the Discord embed / themeColor.
  post_notification \
    "⚠️ OCI 課金検知 / OCI charge detected" \
    "Always Free 枠を超えた請求が発生しました。当月実績: \$${SPEND}。OCI コンソールで内訳を確認してください。/ A charge beyond Always Free was detected. Month-to-date: \$${SPEND}. Check the OCI console. (OCI billing data lags up to ~24h, so this is not real-time.)" \
    15158332
  : > "$SENTINEL"
  echo "[billing-check] ALERT posted (spend=$SPEND, month=$MONTH)"
else
  echo "[billing-check] no charge (spend=$SPEND) — Always Free OK"
fi
