#!/usr/bin/env bash
# post-notification.sh — service-agnostic notification poster.
# Sourced by daily-progress.sh and event-watch.sh.
#
# Reads .env for:
#   NOTIFICATION_SERVICE   one of: discord | slack | teams
#   NOTIFICATION_WEBHOOK_URL  the webhook URL for that service
#
# Usage (from sourcing script):
#   post_notification "<title>" "<body markdown>" "<color int>"
#
# Each service has a slightly different payload schema:
#
# Discord  — Embed with title / description / color / timestamp / footer
# Slack    — `text` + Block Kit (= Markdown + a section block with bold title)
# Teams    — MessageCard with themeColor / title / text
#
# All three support inbound webhooks without any auth beyond the URL itself.

post_notification() {
  local title="$1"
  local body="$2"
  local color_int="${3:-5814783}"   # default: Discord-blue
  local service="${NOTIFICATION_SERVICE:-discord}"
  local url="${NOTIFICATION_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-}}"  # back-compat

  [ -n "$url" ] || { echo "::error:: NOTIFICATION_WEBHOOK_URL not set; cannot post" >&2; return 1; }

  case "$service" in
    discord)
      _post_discord "$url" "$title" "$body" "$color_int"
      ;;
    slack)
      _post_slack "$url" "$title" "$body"
      ;;
    teams)
      _post_teams "$url" "$title" "$body" "$color_int"
      ;;
    *)
      echo "::error:: unknown NOTIFICATION_SERVICE '$service' (expected discord|slack|teams)" >&2
      return 1
      ;;
  esac
}

_post_discord() {
  local url="$1" title="$2" body="$3" color_int="$4"
  local payload
  payload=$(jq -n \
    --arg title "$title" \
    --arg description "$body" \
    --argjson color "$color_int" \
    '{
      embeds: [{
        title: $title,
        description: $description,
        color: $color,
        timestamp: (now | todateiso8601)
      }]
    }')
  curl -fsS -X POST -H 'Content-Type: application/json' -d "$payload" "$url" >/dev/null
}

_post_slack() {
  local url="$1" title="$2" body="$3"
  # Slack incoming webhooks support either {text: "..."} for simple posts
  # or Block Kit for richer layout. We use Block Kit so the title is
  # visually distinct from the body (mirroring Discord embeds).
  local payload
  payload=$(jq -n \
    --arg title "$title" \
    --arg body "$body" \
    '{
      text: $title,
      blocks: [
        { type: "header", text: { type: "plain_text", text: $title, emoji: true } },
        { type: "section", text: { type: "mrkdwn", text: $body } }
      ]
    }')
  curl -fsS -X POST -H 'Content-Type: application/json' -d "$payload" "$url" >/dev/null
}

_post_teams() {
  local url="$1" title="$2" body="$3" color_int="$4"
  # MessageCard color is a hex string (no leading #).
  local hex
  hex=$(printf '%06X' "$color_int")
  local payload
  payload=$(jq -n \
    --arg title "$title" \
    --arg body "$body" \
    --arg hex "$hex" \
    '{
      "@type": "MessageCard",
      "@context": "http://schema.org/extensions",
      themeColor: $hex,
      summary: $title,
      title: $title,
      text: $body
    }')
  curl -fsS -X POST -H 'Content-Type: application/json' -d "$payload" "$url" >/dev/null
}
