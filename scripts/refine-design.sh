#!/usr/bin/env bash
# refine-design.sh — apply a small user-requested edit to a screen's
# page-mock PNG (and its parts-grid PNGs, if Codex regenerates them too)
# by resuming the project-wide image-generation Codex session so brand
# decisions (palette / typography / illustration style / character design)
# are preserved across every refinement.
#
# Image-only: HTML refinements are done by Claude directly with the Edit
# tool — no Codex session involved.
#
# The session contains every screen on every platform for this project,
# so the prompt explicitly names the target screen + platform to avoid
# editing the wrong one.
#
# Usage:
#   bash scripts/refine-design.sh <root> <platform> <screen-name> "<change-request>"
#
# Example:
#   bash scripts/refine-design.sh /Users/me/myproj web Login \
#     "Make the primary button corners more rounded"

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_NAME="${3:?screen name required}"
CHANGE="${4:?change request text required}"

SESSION_FILE="$ROOT/.my-harness/codex-session-design-image.txt"
[ -f "$SESSION_FILE" ] || {
  echo "::error:: $SESSION_FILE missing — run gen-page-parts.sh first" >&2
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
OUT="$ROOT/.my-harness/codex-page-${PLATFORM}-${SCREEN_SLUG}-r$(date +%s).md"

bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --out "$OUT" \
  "Apply this change to the '$SCREEN_NAME' screen on '$PLATFORM': $CHANGE. Regenerate and overwrite the same PNG path. If the parts grid for this screen is affected, regenerate it too in EDIT mode against the new page mock, preserving every immutable style invariant from earlier turns."
