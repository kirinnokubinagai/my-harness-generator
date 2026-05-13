#!/usr/bin/env bash
# ensure-notification-webhook.sh — capture or refresh the project's
# notification webhook URL (Discord / Slack / Teams) and persist it.
#
# Persists to <root>/.my-harness/.notification.env:
#   NOTIFICATION_SERVICE=discord|slack|teams
#   NOTIFICATION_WEBHOOK_URL=<url>
#
# That file is added to .gitignore by the parent /my-harness-init flow.
# It is *separate* from .my-harness/.config because it contains a
# secret (the webhook URL) — .config is committed for some projects
# (without secrets); .notification.env never is.
#
# Usage:
#   bash ensure-notification-webhook.sh <root> <service> [<existing-url>]
#
#     service     = discord | slack | teams | none
#     existing-url= optional. If supplied AND looks-valid, it's saved
#                   as-is without prompting (used when SKILL.md already
#                   collected the URL via AskUserQuestion).
#
# When called with service=none, the .notification.env is wiped and
# script exits 0 (= user opted out / disabling notifications).
#
# The script does NOT itself prompt — it relies on the caller (Claude
# Code running my-harness-init Phase 1) to gather the URL via
# AskUserQuestion. This keeps the bash side dumb and the interactive
# part inside the skill where AskUserQuestion lives.

set -u

ROOT="${1:?root required}"
SERVICE="${2:?service required (discord|slack|teams|none)}"
PROVIDED_URL="${3:-}"

# Helper: validate webhook URL shape per service.
validate_url() {
  local url="$1" service="$2"
  case "$service" in
    discord)
      [[ "$url" =~ ^https://(discord\.com|discordapp\.com)/api/webhooks/[0-9]+/[A-Za-z0-9._-]+ ]] || {
        echo "::error:: Discord webhook URL must look like https://discord.com/api/webhooks/<id>/<token>" >&2
        return 1
      }
      ;;
    slack)
      [[ "$url" =~ ^https://hooks\.slack\.com/services/[A-Z0-9]+/[A-Z0-9]+/[A-Za-z0-9]+$ ]] || {
        echo "::error:: Slack webhook URL must look like https://hooks.slack.com/services/T.../B.../xxx" >&2
        return 1
      }
      ;;
    teams)
      # Teams Incoming Webhook (legacy outlook.office.com or new prod-XX.* )
      [[ "$url" =~ ^https://([A-Za-z0-9.-]+\.office\.com|[A-Za-z0-9.-]+\.webhook\.office\.com)/ ]] || {
        echo "::error:: Teams webhook URL must look like https://outlook.office.com/webhook/... or https://<tenant>.webhook.office.com/..." >&2
        return 1
      }
      ;;
  esac
  return 0
}

write_env() {
  local out="$1" service="$2" url="$3"
  # Preserve other keys (= GH_TOKEN written by ensure-github-pat.sh) by
  # filtering them out before re-appending. Without this merge step,
  # running ensure-notification-webhook.sh after ensure-github-pat.sh
  # would wipe GH_TOKEN.
  local tmp
  tmp="$(mktemp)"
  if [ -f "$out" ]; then
    grep -vE '^(NOTIFICATION_SERVICE=|NOTIFICATION_WEBHOOK_URL=|# Auto-written by scripts/ensure-notification-webhook.sh|# Re-run /my-harness-init)' "$out" > "$tmp" || true
  fi
  {
    echo "# Auto-written by scripts/ensure-notification-webhook.sh — do not edit by hand."
    echo "# Re-run /my-harness-init or scripts/ensure-notification-webhook.sh to change."
    echo "NOTIFICATION_SERVICE=$service"
    echo "NOTIFICATION_WEBHOOK_URL=$url"
    cat "$tmp"
  } > "$out"
  rm -f "$tmp"
  chmod 600 "$out"
}

case "$SERVICE" in
  discord|slack|teams|none) : ;;
  *)
    echo "::error:: invalid service '$SERVICE' — expected discord|slack|teams|none" >&2
    exit 1
    ;;
esac

mkdir -p "$ROOT/.my-harness"
OUT="$ROOT/.my-harness/.notification.env"

# Opt-out: clear the file.
if [ "$SERVICE" = "none" ]; then
  if [ -f "$OUT" ]; then
    rm -f "$OUT"
    echo "[notification] disabled — removed $OUT"
  else
    echo "[notification] disabled (no prior config)"
  fi
  exit 0
fi

# URL provided directly → validate shape, save.
if [ -n "$PROVIDED_URL" ]; then
  validate_url "$PROVIDED_URL" "$SERVICE" || exit 2
  write_env "$OUT" "$SERVICE" "$PROVIDED_URL"
  echo "[notification] saved $SERVICE webhook to $OUT"
  exit 0
fi

# No URL provided → the caller must run again with one. We exit with
# a clear hint so the skill knows it needs to prompt the user.
echo "::error:: no webhook URL provided. Caller (SKILL.md) should AskUserQuestion to obtain it, then re-invoke with the URL as arg 3." >&2
exit 3
