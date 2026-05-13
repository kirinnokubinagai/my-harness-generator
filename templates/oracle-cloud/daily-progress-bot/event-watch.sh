#!/usr/bin/env bash
# event-watch.sh — runs every hour. Polls GitHub for events since the
# last invocation, asks Claude to summarize what's new in Japanese,
# and posts to Discord. Stays silent (no Discord post) when nothing
# changed since the last run.
#
# Difference from daily-progress.sh:
#   daily-progress.sh = once a day at 18:00, broad 24h summary
#   event-watch.sh    = once an hour, narrow "what changed since last hour"
#                       summary; only posts when there's something to say.
#
# Uses the same .env + same Claude Pro/Max subscription. The "last run
# timestamp" is persisted at ~/daily-progress-bot/.last-event-watch
# so successive runs see only the delta.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && set -a && . "$SCRIPT_DIR/.env" && set +a

: "${CLAUDE_CODE_OAUTH_TOKEN:?must be set}"
: "${NOTIFICATION_WEBHOOK_URL:=${DISCORD_WEBHOOK_URL:-}}"
: "${NOTIFICATION_WEBHOOK_URL:?must be set (Discord/Slack/Teams webhook URL)}"
: "${NOTIFICATION_SERVICE:=discord}"
: "${REPO_OWNER:?must be set}"
: "${REPO_NAME:?must be set}"
: "${GH_TOKEN:=${GITHUB_TOKEN:-}}"
LANG_TAG="${LANG_TAG:-ja}"

command -v claude >/dev/null 2>&1 || { echo "::error:: claude CLI not on PATH" >&2; exit 1; }
command -v gh     >/dev/null 2>&1 || { echo "::error:: gh CLI required" >&2; exit 1; }
command -v jq     >/dev/null 2>&1 || { echo "::error:: jq required" >&2; exit 1; }
command -v curl   >/dev/null 2>&1 || { echo "::error:: curl required" >&2; exit 1; }

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/post-notification.sh"

export GH_TOKEN

STATE_FILE="$SCRIPT_DIR/.last-event-watch"

# Read last-run timestamp; default to 1 hour ago on first invocation.
if [ -f "$STATE_FILE" ]; then
  since=$(cat "$STATE_FILE")
else
  since=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
          || date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)
fi
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

EVENTS_FILE="$(mktemp)"
trap 'rm -f "$EVENTS_FILE"' EXIT

# ---- 1. Collect GitHub events since $since ----
{
  echo "Window: $since → $now"
  echo
  echo "### New / updated issues"
  gh issue list --repo "$REPO_OWNER/$REPO_NAME" --search "updated:>$since" --state all \
    --json number,title,state,labels,author --jq '.[] | "- #\(.number) [\(.state)] \(.title)  by \(.author.login)  labels: \([.labels[].name] | join(","))"' 2>/dev/null \
    || echo "(none)"

  echo
  echo "### New / updated PRs"
  gh pr list --repo "$REPO_OWNER/$REPO_NAME" --search "updated:>$since" --state all \
    --json number,title,state,isDraft,author --jq '.[] | "- #\(.number) [\(.state)\(if .isDraft then "/draft" else "" end)] \(.title) by \(.author.login)"' 2>/dev/null \
    || echo "(none)"

  echo
  echo "### Workflow runs completed in window"
  gh run list --repo "$REPO_OWNER/$REPO_NAME" --limit 20 \
    --json name,status,conclusion,createdAt,headBranch \
    --jq --arg since "$since" '.[] | select(.createdAt > $since) | "- [\(.conclusion)] \(.name) on \(.headBranch) at \(.createdAt)"' 2>/dev/null \
    || echo "(none)"

  echo
  echo "### Open priority/p1 issues (always shown — these are top priority)"
  gh issue list --repo "$REPO_OWNER/$REPO_NAME" --label "priority/p1" --state open \
    --json number,title --jq '.[] | "- #\(.number) \(.title)"' 2>/dev/null \
    || echo "(none)"
} > "$EVENTS_FILE"

# Check whether there's actually anything new to report. If only the
# "(none)" placeholders are present, skip Discord post entirely (= no
# noise in the channel when the project is quiet).
NEW_COUNT=$(grep -c '^- #' "$EVENTS_FILE" || true)
PRIORITY_OPEN=$(grep -A100 'priority/p1 issues' "$EVENTS_FILE" | grep -c '^- #' || true)

if [ "$NEW_COUNT" -eq 0 ] && [ "$PRIORITY_OPEN" -eq 0 ]; then
  echo "[event-watch] nothing to report since $since — skip"
  echo "$now" > "$STATE_FILE"
  exit 0
fi

# ---- 2. Ask Claude to summarize ----
if [ "$LANG_TAG" = "ja" ]; then
  PROMPT_INSTRUCTION="次の GitHub 活動データから、1 時間以内に起きた重要な変化のみを 1-3 行で日本語要約してください。
- 通常の作業 (新規 commit、normal な PR opened/merged) は触れない。
- 通知すべきもの: priority/p1 の新規 issue, CI failure, 新規 security issue, draft でない PR の opened, 大きな PR の merged, conflict 発生など。
- 既に Discord に出した内容と重複する可能性がある場合は1 行のみ。
- 形式: 各行を絵文字で始める (🔥要対応 / ✅完了 / ✨新規 / 🚧進行中)。
- Markdown 最小限、コードブロック不可。
- 何も特筆すべきイベントが無ければ '_no_report_' とだけ出力。"
else
  PROMPT_INSTRUCTION="From the GitHub activity below, summarize ONLY the notable changes in the last hour, as 1-3 short lines.
- Skip routine work (regular commits, ordinary PR opened/merged).
- Notable = new priority/p1 issue, CI failure, new security issue, non-draft PR opened, large PR merged, conflict, etc.
- Each line starts with an emoji (🔥 needs attention / ✅ done / ✨ new / 🚧 in-progress).
- Minimal markdown, no code blocks.
- If nothing is worth reporting, output ONLY '_no_report_'."
fi

SUMMARY=$(CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN" claude \
  -p "$PROMPT_INSTRUCTION

---

$(cat "$EVENTS_FILE")" \
  --output-format text \
  --model claude-sonnet-4-6 2>/dev/null) || {
  echo "[event-watch] Claude call failed — skip this hour"
  echo "$now" > "$STATE_FILE"
  exit 0
}

# Claude judged "nothing to report" → no Discord post.
if [ -z "$SUMMARY" ] || echo "$SUMMARY" | grep -q '_no_report_'; then
  echo "[event-watch] Claude said nothing notable — skip"
  echo "$now" > "$STATE_FILE"
  exit 0
fi

# ---- 3. Post notification ----
HOUR=$(date +"%H:%M")
TITLE="⏰ $HOUR の最新動向 ($REPO_OWNER/$REPO_NAME)"
post_notification "$TITLE" "$SUMMARY" 16776960
echo "$now" > "$STATE_FILE"
echo "[event-watch] posted to $NOTIFICATION_SERVICE at $(date)"
