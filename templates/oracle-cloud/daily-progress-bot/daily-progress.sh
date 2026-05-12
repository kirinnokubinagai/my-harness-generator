#!/usr/bin/env bash
# daily-progress.sh — once a day, ask Claude to read the project's git
# activity and post a human-readable Japanese summary to Discord.
#
# Designed to run on an Oracle Cloud Always-Free VM (ARM Ampere A1)
# under cron. Uses the user's existing Claude Pro/Max subscription via
# CLAUDE_CODE_OAUTH_TOKEN (so the marginal cost is zero — no API key,
# no per-token billing). Anthropic officially supports this "one human,
# one subscription, one beneficiary" headless usage of Claude Code CLI.
#
# Required env (sourced from .env):
#   CLAUDE_CODE_OAUTH_TOKEN   — your Pro/Max OAuth token (claude login output)
#   DISCORD_WEBHOOK_URL       — Discord channel webhook to post into
#   GH_TOKEN (or GITHUB_TOKEN) — read-only token for `gh` CLI (public repos
#                                can sometimes skip this, but private need it)
#   REPO_OWNER, REPO_NAME     — e.g. acme / myapp
#
# Optional env:
#   LANG_TAG                  — "ja" (default) or "en" for Claude's summary
#   LOOKBACK_HOURS            — how far back to scan (default 24)

set -u

# Load .env from the script's directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && set -a && . "$SCRIPT_DIR/.env" && set +a

: "${CLAUDE_CODE_OAUTH_TOKEN:?must be set (run \`claude login\` on a desktop machine, copy token here)}"
# Either NOTIFICATION_WEBHOOK_URL (preferred, multi-service) or the legacy
# DISCORD_WEBHOOK_URL must be set.
: "${NOTIFICATION_WEBHOOK_URL:=${DISCORD_WEBHOOK_URL:-}}"
: "${NOTIFICATION_WEBHOOK_URL:?must be set (Discord/Slack/Teams webhook URL — see your services docs)}"
: "${NOTIFICATION_SERVICE:=discord}"
: "${REPO_OWNER:?must be set}"
: "${REPO_NAME:?must be set}"
: "${GH_TOKEN:=${GITHUB_TOKEN:-}}"
LANG_TAG="${LANG_TAG:-ja}"
LOOKBACK_HOURS="${LOOKBACK_HOURS:-24}"

# Pull in the multi-service notification helper.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/post-notification.sh"

command -v claude >/dev/null 2>&1 || { echo "::error:: claude CLI not on PATH (install: npm i -g @anthropic-ai/claude-code)" >&2; exit 1; }
command -v gh     >/dev/null 2>&1 || { echo "::error:: gh CLI required (https://cli.github.com/)" >&2; exit 1; }
command -v jq     >/dev/null 2>&1 || { echo "::error:: jq required" >&2; exit 1; }
command -v curl   >/dev/null 2>&1 || { echo "::error:: curl required" >&2; exit 1; }

export GH_TOKEN

# ---- 1. Collect GitHub activity ----
# Last N hours of: commits on the default branch, opened/closed issues + PRs,
# latest CI workflow run status.
since=$(date -u -d "${LOOKBACK_HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -v-${LOOKBACK_HOURS}H +%Y-%m-%dT%H:%M:%SZ)   # GNU vs BSD date

ACTIVITY_FILE="$(mktemp)"
trap 'rm -f "$ACTIVITY_FILE"' EXIT

{
  echo "## Repo: $REPO_OWNER/$REPO_NAME"
  echo "## Window: since $since"
  echo
  echo "### Commits (default branch)"
  gh api "repos/$REPO_OWNER/$REPO_NAME/commits?since=$since&per_page=50" \
    --jq '.[] | "- \(.commit.author.name): \(.commit.message | split("\n") | .[0]) [\(.sha[0:7])]"' 2>/dev/null \
    || echo "(no commits or API unreachable)"
  echo
  echo "### Issues opened in window"
  gh issue list --repo "$REPO_OWNER/$REPO_NAME" --search "created:>=$since" --state open \
    --json number,title,labels --jq '.[] | "- #\(.number) \(.title) (labels: \([.labels[].name] | join(", ")))"' 2>/dev/null \
    || echo "(none)"
  echo
  echo "### Issues closed in window"
  gh issue list --repo "$REPO_OWNER/$REPO_NAME" --search "closed:>=$since" --state closed \
    --json number,title --jq '.[] | "- #\(.number) \(.title)"' 2>/dev/null \
    || echo "(none)"
  echo
  echo "### PRs in window"
  gh pr list --repo "$REPO_OWNER/$REPO_NAME" --search "updated:>=$since" --state all \
    --json number,title,state,isDraft --jq '.[] | "- #\(.number) [\(.state)\(if .isDraft then "/draft" else "" end)] \(.title)"' 2>/dev/null \
    || echo "(none)"
  echo
  echo "### Latest workflow runs (top 5)"
  gh run list --repo "$REPO_OWNER/$REPO_NAME" --limit 5 \
    --json name,status,conclusion,createdAt --jq '.[] | "- \(.name): \(.status)/\(.conclusion) at \(.createdAt)"' 2>/dev/null \
    || echo "(none)"
  echo
  echo "### Open issues with priority/p1 (= security or other top-priority work)"
  gh issue list --repo "$REPO_OWNER/$REPO_NAME" --label "priority/p1" --state open \
    --json number,title --jq '.[] | "- #\(.number) \(.title)"' 2>/dev/null \
    || echo "(none)"
} > "$ACTIVITY_FILE"

# ---- 2. Ask Claude to summarize ----
if [ "$LANG_TAG" = "ja" ]; then
  PROMPT_INSTRUCTION="次のリポジトリ活動データを元に、日次進捗を 3〜5 個の箇条書きで日本語で要約してください。
重要事項 (priority/p1 issue, CI failure, 大きな機能追加, セキュリティ問題など) を最初に。
箇条書きは絵文字で始めて (✅成功 / 🚧進行中 / 🔥要対応 / ✨新規 など)、簡潔に。
Discord に投稿するので Markdown は最小限 (太字 ** のみ可)、コードブロックは使わない。"
else
  PROMPT_INSTRUCTION="Based on the repository activity below, summarize today's progress as 3-5 bullet points.
Start with anything urgent (priority/p1 issues, CI failures, major features, security findings).
Prefix each bullet with an emoji (✅ done / 🚧 in-progress / 🔥 needs attention / ✨ new).
Keep it concise — this will be posted to Discord. Minimal markdown (only **bold**), no code blocks."
fi

SUMMARY=$(CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN" claude \
  -p "$PROMPT_INSTRUCTION

---

$(cat "$ACTIVITY_FILE")" \
  --output-format text \
  --model claude-sonnet-4-6 2>/dev/null) || {
  SUMMARY="⚠️ daily-progress: Claude の要約取得に失敗しました。VM の log を確認してください。"
}

[ -z "$SUMMARY" ] && SUMMARY="(本日の活動なし、または取得不可)"

# ---- 3. Post notification ----
TODAY=$(date +"%Y-%m-%d")
TITLE="📊 $TODAY の進捗 ($REPO_OWNER/$REPO_NAME)"
post_notification "$TITLE" "$SUMMARY" 5814783

NOW=$(date)
echo "[daily-progress] posted to $NOTIFICATION_SERVICE at $NOW"

