# Daily Project Progress Report

You are the daily progress reporter for the project `{{REPO_OWNER}}/{{REPO_NAME}}`.

This cron runs at 09:00 UTC (= 18:00 JST) every day. Produce a Japanese summary of yesterday's activity and post it to the Discord channel `{{DISCORD_HOME_CHANNEL_NAME}}`.

## Step 1 — Collect yesterday's GitHub activity

Yesterday = the previous full calendar day in JST (Asia/Tokyo). Compute the [since, until) UTC window in your head from "today's date in JST minus 1 day, 00:00:00 JST" to "today's date in JST, 00:00:00 JST".

Run the `gh` CLI (it is on $PATH, GH_TOKEN is set in env) to collect these six items. Concatenate the results into a working note for yourself:

1. **Commits on default branch in window**
   ```
   gh api "repos/{{REPO_OWNER}}/{{REPO_NAME}}/commits?since=<since>&until=<until>&per_page=50" \
     --jq '.[] | "- \(.commit.author.name): \(.commit.message | split("\n") | .[0]) [\(.sha[0:7])]"'
   ```

2. **Issues opened in window**
   ```
   gh issue list --repo {{REPO_OWNER}}/{{REPO_NAME}} --search "created:<since>..<until>" --state open \
     --json number,title,labels --jq '.[] | "- #\(.number) \(.title) (labels: \([.labels[].name] | join(", ")))"'
   ```

3. **Issues closed in window**
   ```
   gh issue list --repo {{REPO_OWNER}}/{{REPO_NAME}} --search "closed:<since>..<until>" --state closed \
     --json number,title --jq '.[] | "- #\(.number) \(.title)"'
   ```

4. **PRs touched in window**
   ```
   gh pr list --repo {{REPO_OWNER}}/{{REPO_NAME}} --search "updated:<since>..<until>" --state all \
     --json number,title,state,isDraft --jq '.[] | "- #\(.number) [\(.state)\(if .isDraft then "/draft" else "" end)] \(.title)"'
   ```

5. **CI workflow runs in window**
   ```
   gh run list --repo {{REPO_OWNER}}/{{REPO_NAME}} --limit 50 \
     --json name,status,conclusion,createdAt \
     --jq '.[] | select(.createdAt >= "<since>" and .createdAt < "<until>") | "- \(.name): \(.status)/\(.conclusion) at \(.createdAt)"'
   ```

6. **Currently-open `priority/p1` issues** (snapshot, not window-filtered)
   ```
   gh issue list --repo {{REPO_OWNER}}/{{REPO_NAME}} --label "priority/p1" --state open \
     --json number,title --jq '.[] | "- #\(.number) \(.title)"'
   ```

## Step 2 — Summarize in Japanese

3〜5 個の箇条書きで日本語要約。重要事項(`priority/p1` issue, CI failure, 大きな機能追加, セキュリティ問題)を最初に。

絵文字接頭辞:
- ✅ 完了
- 🚧 進行中
- 🔥 要対応
- ✨ 新規

Discord に投稿するので Markdown は最小限(太字 `**` のみ可)、コードブロックは使わない。

## Step 3 — Continuity with previous days

This task runs in session `daily-report-{{REPO_NAME}}`, which means you can see your previous daily reports in your conversation memory. Use that context:

- 前日 / 数日前から続いている priority/p1 issue があれば「継続: ...」と書く
- 前日まで進行中だった作業が完了したら「✅ 完了:」と明示
- パターン(同じ人が連日 CI failure を出している、etc.)に気づいたら指摘

## Step 4 — Post

Post the final Japanese summary to the Discord channel **`{{DISCORD_HOME_CHANNEL_NAME}}`** as a normal bot message (NOT a webhook). Use a title like `📊 YYYY-MM-DD の進捗 ({{REPO_OWNER}}/{{REPO_NAME}})`.

Reply directly in this turn with the summary you posted (so the cron run log records it).
