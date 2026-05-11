#!/usr/bin/env bash
# gen-page-html.sh — convert an approved page-mock PNG into a self-contained
# Tailwind HTML file at dev/docs/design/page-<platform>-<screen-slug>.html.
#
# Phase 5 deliverable: design-fidelity HTML. No JS, no state, no React. Plain
# Tailwind utility classes plus <img> references to the cropped parts PNGs
# (clouds, illustrations, brand marks — anything that's not pure HTML).
#
# Opens in the browser via file:// — no dev server required. Acts as the
# pixel-level source of truth that the implementation phase converts to TSX.
#
# Pre-reqs: gen-page-parts.sh and crop-parts.sh must have run for this
# (platform, screen-slug). manifest.json and page PNG must exist.
#
# Usage:
#   bash scripts/gen-page-html.sh <root> <platform> <screen-slug> <project-name>

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_SLUG="${3:?screen-slug required}"
PROJECT_NAME="${4:?project name required}"

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_TMPL="$HARNESS_DIR/prompts/codex-page-to-html.md"
[ -f "$PROMPT_TMPL" ] || { echo "::error:: $PROMPT_TMPL not found" >&2; exit 1; }

PAGE_PNG="$ROOT/dev/docs/design/page-${PLATFORM}-${SCREEN_SLUG}.png"
MANIFEST="$ROOT/dev/public/design/parts/${PLATFORM}/${SCREEN_SLUG}/manifest.json"
OUT_HTML="$ROOT/dev/docs/design/page-${PLATFORM}-${SCREEN_SLUG}.html"

[ -f "$PAGE_PNG" ]  || { echo "::error:: page PNG missing: $PAGE_PNG  (run gen-page-parts.sh first)" >&2; exit 1; }
[ -f "$MANIFEST" ]  || { echo "::error:: manifest missing: $MANIFEST  (run crop-parts.sh first)" >&2; exit 1; }

mkdir -p "$ROOT/.my-harness"

# Build prompt: substitute placeholders + append parts manifest contents.
MANIFEST_JSON=$(cat "$MANIFEST")
BASE_PROMPT=$(sed \
  -e "s|<PROJECT_NAME>|$PROJECT_NAME|g" \
  -e "s|<PLATFORM>|$PLATFORM|g" \
  -e "s|<SCREEN_SLUG>|$SCREEN_SLUG|g" \
  -e "s|<OUT_HTML>|$OUT_HTML|g" \
  -e "s|<PAGE_PNG>|$PAGE_PNG|g" \
  "$PROMPT_TMPL")

PROMPT="$BASE_PROMPT

---

Parts manifest (every available transparent PNG asset for this screen):

\`\`\`json
$MANIFEST_JSON
\`\`\`
"

# One Codex HTML-generation session per project — NOT per screen, NOT per
# platform. Shares the Tailwind palette, spacing conventions, and component
# style across every screen in the project. The image-generation session is
# kept separate (design-image-<project>) so that image_gen tool context
# does not pollute HTML generation, and vice versa.
PROJECT_SLUG=$(printf '%s' "$PROJECT_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')
PROJECT_SLUG=${PROJECT_SLUG:-project}
SESSION_KEY="design-html-${PROJECT_SLUG}"
echo "$SESSION_KEY" > "$ROOT/.my-harness/codex-session-design-html.txt"

# Remove any prior HTML so the existence check is meaningful.
rm -f "$OUT_HTML"

RESPONSE_INIT="$ROOT/.my-harness/codex-html-${PLATFORM}-${SCREEN_SLUG}.md"

bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --context "$PAGE_PNG" "$MANIFEST" \
  --out "$RESPONSE_INIT" \
  "$PROMPT"

is_html() {
  [ -f "$1" ] && grep -qi '<!DOCTYPE html' "$1" 2>/dev/null && grep -q '</html>' "$1" 2>/dev/null
}

MAX_RETRY=${HARNESS_GEN_RETRY:-3}
RETRY=0
while ! is_html "$OUT_HTML"; do
  RETRY=$(( RETRY + 1 ))
  if [ "$RETRY" -gt "$MAX_RETRY" ]; then
    echo "::error:: HTML not produced after $MAX_RETRY attempts. Session '$SESSION_KEY' preserved." >&2
    [ -f "$OUT_HTML" ] && echo "::error:: file exists but is not valid HTML — first 200 chars: $(head -c 200 "$OUT_HTML")" >&2
    exit 2
  fi

  NUDGE="HTML file is missing at $OUT_HTML (or is not a complete HTML document — must start with <!DOCTYPE html> and end with </html>). Write the complete HTML to that exact path now using your file-write tool. Do NOT paste the HTML in your text response."
  echo "::warning:: attempt $RETRY/$MAX_RETRY failed; nudging: HTML missing or incomplete" >&2

  RESPONSE_RETRY="$ROOT/.my-harness/codex-html-${PLATFORM}-${SCREEN_SLUG}-r${RETRY}.md"
  bash "$HARNESS_DIR/scripts/codex-ask.sh" \
    --role designer \
    --session "$SESSION_KEY" \
    --out "$RESPONSE_RETRY" \
    "$NUDGE"
done

echo
echo "html:     $OUT_HTML"
echo "session:  $SESSION_KEY"
echo "open:     file://$OUT_HTML"

# Auto-open in default browser unless suppressed.
# shellcheck disable=SC1091
. "$HARNESS_DIR/scripts/lib/open-file.sh"
open_file "$OUT_HTML"
