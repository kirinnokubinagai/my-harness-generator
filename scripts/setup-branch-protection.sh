#!/usr/bin/env bash
# Summary: Applies GitHub branch protection rules in bulk using the gh CLI.
#          Enforces force-push prohibition, required status checks, and required PR reviews
#          on main / stage / dev.
# Usage: bash .harness/scripts/setup-branch-protection.sh <owner/repo>
set -euo pipefail
REPO="${1:?owner/repo required}"

# Required status check names (must match the job names exposed by reusable workflows)
REQUIRED_CHECKS='[
  "quality",
  "e2e",
  "security",
  "claude-review"
]'

apply_protection() {
  local BRANCH="$1"
  local APPROVALS="$2"
  echo "[branch-protection] Applying protection to $BRANCH"
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

# Enable auto-merge (repository setting)
gh api -X PATCH "repos/$REPO" \
  -F allow_auto_merge=true \
  -F allow_merge_commit=true \
  -F allow_squash_merge=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true

echo "[branch-protection] Done. Force-push prohibited, required status checks, and required reviews are configured."
