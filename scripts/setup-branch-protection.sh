#!/usr/bin/env bash
# 概要: GitHub の branch protection を gh CLI で一括設定する。
#       main / stage に対して force-push 禁止、必須 status check、必須 PR レビューを適用する。
# 使い方: bash .harness/scripts/setup-branch-protection.sh <owner/repo>
set -euo pipefail
REPO="${1:?owner/repo required}"

# 必須 status check 名（reusable workflow が exposing する job 名と一致させる）
REQUIRED_CHECKS='[
  "quality",
  "e2e",
  "security",
  "claude-review"
]'

apply_protection() {
  local BRANCH="$1"
  local APPROVALS="$2"
  echo "[branch-protection] $BRANCH に保護を適用"
  gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
    -H "Accept: application/vnd.github+json" \
    -f required_status_checks[strict]=true \
    -F "required_status_checks[contexts]=$REQUIRED_CHECKS" \
    -f enforce_admins=true \
    -F "required_pull_request_reviews[required_approving_review_count]=$APPROVALS" \
    -f required_pull_request_reviews[dismiss_stale_reviews]=true \
    -f required_pull_request_reviews[require_code_owner_reviews]=true \
    -f required_linear_history=false \
    -F "restrictions=null" \
    -f allow_force_pushes=false \
    -f allow_deletions=false \
    -f required_conversation_resolution=true \
    -f lock_branch=false \
    -f block_creations=false
}

apply_protection "main"  2
apply_protection "stage" 1
apply_protection "dev"   1

# auto-merge を許可（リポジトリ設定）
gh api -X PATCH "repos/$REPO" \
  -F allow_auto_merge=true \
  -F allow_merge_commit=true \
  -F allow_squash_merge=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true

echo "[branch-protection] 完了。force-push 禁止・必須 status check・必須レビューを設定しました。"
