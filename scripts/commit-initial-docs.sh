#!/usr/bin/env bash
# commit-initial-docs.sh — commit the initial README.md + CLAUDE.md generated
# at the end of Phase 8 with a language-appropriate commit message.
#
# Runs inside <root>/dev. Uses a fixed harness-bot identity so the commit
# never depends on the user's local git config. --no-verify skips repo hooks
# (the docs are freshly generated and pass none of the project's lints yet).
#
# Usage:
#   bash scripts/commit-initial-docs.sh <root> <lang>
#
# Lang values: "ja" (Japanese), anything else falls back to English.

set -u

ROOT="${1:?root required}"
LANG_TAG="${2:?lang required (ja|en|...)}"

DEV_DIR="$ROOT/dev"
[ -d "$DEV_DIR" ] || { echo "::error:: $DEV_DIR not found" >&2; exit 1; }

cd "$DEV_DIR" || exit 1

# Only commit if at least one of the two files exists.
HAS_README=0; [ -f README.md ] && HAS_README=1
HAS_CLAUDE=0; [ -f CLAUDE.md ] && HAS_CLAUDE=1
if [ "$HAS_README" -eq 0 ] && [ "$HAS_CLAUDE" -eq 0 ]; then
  echo "::warning:: neither README.md nor CLAUDE.md present in $DEV_DIR — nothing to commit" >&2
  exit 0
fi
[ "$HAS_README" -eq 1 ] && git add README.md
[ "$HAS_CLAUDE" -eq 1 ] && git add CLAUDE.md

case "$LANG_TAG" in
  ja|JA|ja-JP) MSG="docs: README.md と CLAUDE.md の初版を spec から生成" ;;
  *)           MSG="docs: generate initial README.md and CLAUDE.md from spec" ;;
esac

git -c user.name="harness-bot" -c user.email="harness@local" \
  commit --no-verify -m "$MSG"
