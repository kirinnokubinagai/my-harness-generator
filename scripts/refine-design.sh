#!/usr/bin/env bash
# refine-design.sh — apply a small user-requested edit to one already-generated
# screen artifact, resuming the project-wide Codex session so brand decisions
# (palette / typography / icon language) are preserved across every refinement.
#
# Two modes:
#   image  — resume design-image-<project-slug>; Codex overwrites the screen's
#            page PNG (and grid PNGs if relevant).
#   html   — resume design-html-<project-slug>;  Codex overwrites the screen's
#            Tailwind HTML file.
#
# Because each project-wide session contains every screen on every platform,
# the prompt explicitly names the target screen + platform so Codex does not
# accidentally edit the wrong one.
#
# Usage:
#   bash scripts/refine-design.sh <kind> <root> <platform> <screen-name> "<change-request>"
#
# Example:
#   bash scripts/refine-design.sh image /Users/me/myproj web Login \
#     "Make the primary button corners more rounded"

set -u

KIND="${1:?kind required (image|html)}"
ROOT="${2:?root required}"
PLATFORM="${3:?platform required}"
SCREEN_NAME="${4:?screen name required}"
CHANGE="${5:?change request text required}"

case "$KIND" in
  image)
    SESSION_FILE="$ROOT/.my-harness/codex-session-design-image.txt"
    PREFIX="codex-page"
    TAIL="Regenerate and overwrite the same PNG path."
    ;;
  html)
    SESSION_FILE="$ROOT/.my-harness/codex-session-design-html.txt"
    PREFIX="codex-html"
    TAIL="Overwrite the same HTML file."
    ;;
  *)
    echo "::error:: unknown kind '$KIND' — expected 'image' or 'html'" >&2
    exit 1
    ;;
esac

[ -f "$SESSION_FILE" ] || {
  echo "::error:: $SESSION_FILE missing — run gen-page-${KIND/image/parts}.sh or gen-page-html.sh first" >&2
  exit 1
}
SESSION_KEY=$(cat "$SESSION_FILE")

# screen-name → kebab-case slug
SCREEN_SLUG=$(printf '%s' "$SCREEN_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | tr ' /' '--' \
  | sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')
SCREEN_SLUG=${SCREEN_SLUG:-screen}

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.my-harness"
OUT="$ROOT/.my-harness/${PREFIX}-${PLATFORM}-${SCREEN_SLUG}-r$(date +%s).md"

bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --out "$OUT" \
  "Apply this change to the '$SCREEN_NAME' screen on '$PLATFORM': $CHANGE. $TAIL"
