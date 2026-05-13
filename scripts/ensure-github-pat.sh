#!/usr/bin/env bash
# ensure-github-pat.sh — capture or refresh the project's GitHub
# read-only Personal Access Token (used by the daily-progress bot
# inside the OCI VM via `gh issue list / gh pr list / gh run list`).
#
# Persists to <root>/.my-harness/.notification.env (alongside the
# webhook URL — same gitignored file, same chmod 600).
#
# Usage:
#   bash ensure-github-pat.sh <root> [<existing-pat>]
#
# If <existing-pat> is empty, the script exits 3 to signal the caller
# (SKILL.md) to AskUserQuestion for it. With a PAT, the script
# validates its shape (`ghp_*`, `github_pat_*`, or 40-hex classic
# token) and writes it.

set -u

ROOT="${1:?root required}"
PROVIDED_PAT="${2:-}"

validate_pat() {
  local pat="$1"
  # NOTE: macOS bash 3.2 rejects 3-digit repetition counts like {30,300},
  # so we keep the upper bound 2-digit. The real GitHub tokens are
  # well under 100 characters past the prefix, so this is safe.
  if [[ "$pat" =~ ^ghp_[A-Za-z0-9_]{36,99}$ ]]; then return 0; fi          # fine-grained / classic w/ prefix
  if [[ "$pat" =~ ^github_pat_[A-Za-z0-9_]{30,99}$ ]]; then return 0; fi   # fine-grained
  if [[ "$pat" =~ ^[a-f0-9]{40}$ ]]; then return 0; fi                     # legacy classic (no prefix)
  echo "::error:: PAT shape not recognized. Expected ghp_..., github_pat_..., or 40-hex classic." >&2
  return 1
}

mkdir -p "$ROOT/.my-harness"
OUT="$ROOT/.my-harness/.notification.env"

if [ -z "$PROVIDED_PAT" ]; then
  echo "::error:: no GitHub PAT provided. Caller should AskUserQuestion to obtain it (READ-only scopes: contents, issues, pull-requests, actions), then re-invoke with the PAT as arg 2." >&2
  exit 3
fi

validate_pat "$PROVIDED_PAT" || exit 2

# Append or update GH_TOKEN line in the same file as the webhook URL.
# We rewrite the file by stripping any prior GH_TOKEN= line and adding
# a fresh one — keeps the file diffable and chmod stable.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
if [ -f "$OUT" ]; then
  grep -v '^GH_TOKEN=' "$OUT" > "$TMP" || true
fi
{
  cat "$TMP"
  echo "GH_TOKEN=$PROVIDED_PAT"
} > "$OUT"
chmod 600 "$OUT"

echo "[notification] saved GH_TOKEN to $OUT"
