#!/usr/bin/env bash
# commit-design-screen.sh — stage and commit a single screen's approved
# design artifacts (page mock + parts grid + cropped transparent parts
# + parts.ts asset map, across whichever form factors were produced).
#
# Called from inside the /my-harness-init Phase 5 Stage 1 loop, after
# the user confirms the screen's mocks look right. Operates on the
# USER'S project repository, not the harness repo.
#
# Per-screen, not per-form-factor: one commit per user OK event covers
# both pc and mobile (or whichever subset was produced).
#
# Idempotent: re-running after a no-op refinement makes no commit
# (git detects no staged change and the script exits 0).
#
# Usage:
#   bash commit-design-screen.sh <root> <screen-slug> [<screen-display-name>]
#
# Notes:
#   - <screen-slug> is the kebab-case slug used in filenames (e.g. `home`).
#   - <screen-display-name> is the human-readable name (e.g. `Home`)
#     used in the commit body. Falls back to <screen-slug> if omitted.

set -u

ROOT="${1:?root required (path to the users project repo)}"
SLUG="${2:?screen-slug required (kebab-case slug used in filenames)}"
SCREEN_NAME="${3:-$SLUG}"

cd "$ROOT" || { echo "::error:: cd to $ROOT failed" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "::error:: $ROOT is not a git repository. Run \`git init\` first, then re-run this script." >&2
  exit 1
}

# Collect every design artifact path that exists for this screen.
# Use space-separated strings (bash 3.2 compatible — no += on arrays).
PATHS_TO_STAGE=""
FF_LIST=""
STAGED_COUNT=0

for ff in pc mobile; do
  HAS_FF=no

  if [ -f "dev/docs/design/page-${ff}-${SLUG}.png" ]; then
    PATHS_TO_STAGE="$PATHS_TO_STAGE dev/docs/design/page-${ff}-${SLUG}.png"
    STAGED_COUNT=$((STAGED_COUNT + 1))
    HAS_FF=yes
  fi

  # parts-grid PNGs — there may be 0, 1, or several per form factor.
  for g in "dev/docs/design/parts-grid-${ff}-${SLUG}"-*.png; do
    if [ -f "$g" ]; then
      PATHS_TO_STAGE="$PATHS_TO_STAGE $g"
      STAGED_COUNT=$((STAGED_COUNT + 1))
      HAS_FF=yes
    fi
  done

  if [ -d "dev/docs/design/parts/${ff}/${SLUG}" ]; then
    PATHS_TO_STAGE="$PATHS_TO_STAGE dev/docs/design/parts/${ff}/${SLUG}"
    STAGED_COUNT=$((STAGED_COUNT + 1))
    HAS_FF=yes
  fi

  if [ -d "dev/src/components/design/${ff}/${SLUG}" ]; then
    PATHS_TO_STAGE="$PATHS_TO_STAGE dev/src/components/design/${ff}/${SLUG}"
    STAGED_COUNT=$((STAGED_COUNT + 1))
    HAS_FF=yes
  fi

  if [ "$HAS_FF" = "yes" ]; then
    FF_LIST="$FF_LIST $ff"
  fi
done

if [ -z "$PATHS_TO_STAGE" ]; then
  echo "::warning:: no design artifacts found for screen slug '$SLUG' under $ROOT/dev/docs/design/ -- nothing to commit." >&2
  echo "  Did gen-page-auto.sh run for this screen? Check the slug spelling." >&2
  exit 0
fi

# shellcheck disable=SC2086
git add -- $PATHS_TO_STAGE

if git diff --staged --quiet; then
  echo "[commit-design] no changes for screen '$SLUG' since last commit -- skip."
  exit 0
fi

# Build FF_STR: trim leading space, replace spaces with +
FF_STR=$(echo "$FF_LIST" | sed 's/^ //' | sed 's/ /+/g')

COMMIT_MSG_FILE=$(mktemp /tmp/commit-design-screen.XXXXXX)
printf 'design(%s): mock approved -- %s\n' "${SLUG}" "${FF_STR}"    > "${COMMIT_MSG_FILE}"
printf '\n'                                                          >> "${COMMIT_MSG_FILE}"
printf 'User confirmed the design mock(s) look right after Phase 5 Stage 1\n' >> "${COMMIT_MSG_FILE}"
printf 'generation/refinement. Auto-committed by commit-design-screen.sh.\n'  >> "${COMMIT_MSG_FILE}"
printf '\n'                                                          >> "${COMMIT_MSG_FILE}"
printf 'Screen:        %s\n' "${SCREEN_NAME}"                       >> "${COMMIT_MSG_FILE}"
printf 'Slug:          %s\n' "${SLUG}"                              >> "${COMMIT_MSG_FILE}"
printf 'Form factors:  %s\n' "${FF_STR}"                           >> "${COMMIT_MSG_FILE}"
printf 'Files staged:  %s\n' "${STAGED_COUNT}"                     >> "${COMMIT_MSG_FILE}"
printf '\n'                                                          >> "${COMMIT_MSG_FILE}"
printf 'Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>\n' >> "${COMMIT_MSG_FILE}"

git commit -F "${COMMIT_MSG_FILE}"
rm -f "${COMMIT_MSG_FILE}"

echo "[commit-design] committed '${SLUG}' (${FF_STR}) -- ${STAGED_COUNT} path(s)."
