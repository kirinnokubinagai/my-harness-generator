#!/usr/bin/env bash
# gen-page-html.sh — convert an approved page-mock PNG into a self-contained
# Tailwind HTML file via Codex.
#
# Why this exists (vs. having Claude write the HTML directly):
#   When USE_CODEX=yes, automating HTML through Codex removes the failure
#   mode where Claude writes HTML from prompt-derived guesses without
#   actually reading the page PNG. Codex receives the PNG as a context
#   attachment and the style_guide as inline invariants — it must visually
#   reference the image to fulfill the prompt. The result is a more
#   reliable "page → HTML" pipeline with no manual hand-off.
#
# Session strategy:
#   Uses a separate Codex session (`design-html-<project-slug>`) from the
#   image-generation session (`design-image-<project-slug>`). image_gen
#   tool turns and file_write turns mix poorly in one session — the model
#   sometimes tries to call image_gen when asked for HTML and vice versa.
#   The HTML session inherits style consistency the OTHER way: by echoing
#   the style_guide JSON (read from the form factor's manifest.json) as
#   invariants in the prompt.
#
# Pre-reqs:
#   - gen-page-parts.sh and crop-parts.sh must have run for this
#     (form-factor, screen-slug) so the PNG and manifest exist.
#
# Usage:
#   bash scripts/gen-page-html.sh <root> <form-factor> <screen-slug> <project-name>

set -u

ROOT="${1:?root required}"
FORM_FACTOR="${2:?form-factor required (pc|mobile|...)}"
SCREEN_SLUG="${3:?screen-slug required}"
PROJECT_NAME="${4:?project name required}"

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_TMPL="$HARNESS_DIR/prompts/codex-page-to-html.md"
[ -f "$PROMPT_TMPL" ] || { echo "::error:: $PROMPT_TMPL not found" >&2; exit 1; }
command -v jq      >/dev/null 2>&1 || { echo "::error:: jq required" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "::error:: python3 required" >&2; exit 3; }

PAGE_PNG="$ROOT/dev/docs/design/page-${FORM_FACTOR}-${SCREEN_SLUG}.png"
MANIFEST="$ROOT/dev/docs/design/parts/${FORM_FACTOR}/${SCREEN_SLUG}/manifest.json"
OUT_HTML="$ROOT/dev/docs/design/page-${FORM_FACTOR}-${SCREEN_SLUG}.html"

[ -f "$PAGE_PNG" ] || { echo "::error:: page PNG missing: $PAGE_PNG  (run gen-page-parts.sh first)" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "::error:: manifest missing: $MANIFEST  (run crop-parts.sh first)" >&2; exit 1; }

mkdir -p "$ROOT/.my-harness"

# Derive the screen name from the slug for readable prompt context.
# (We only have the slug at this layer; gen-page-auto.sh kept the spelled-out
# name. Re-fetching it here would mean passing it through more layers — for
# clarity in the prompt we Title-Case the slug as a reasonable approximation.)
SCREEN_NAME=$(printf '%s' "$SCREEN_SLUG" | sed -E 's/-/ /g; s/(^| )([a-z])/\1\U\2/g')

PROJECT_SLUG=$(printf '%s' "$PROJECT_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')
PROJECT_SLUG=${PROJECT_SLUG:-project}

SESSION_KEY="design-html-${PROJECT_SLUG}"
echo "$SESSION_KEY" > "$ROOT/.my-harness/codex-session-design-html.txt"

STYLE_GUIDE_JSON=$(jq -c '.style_guide // empty' "$MANIFEST" 2>/dev/null)
[ -n "$STYLE_GUIDE_JSON" ] && [ "$STYLE_GUIDE_JSON" != "null" ] || {
  echo "::warning:: style_guide missing from manifest — Codex will improvise palette" >&2
  STYLE_GUIDE_JSON='{}'
}
MANIFEST_JSON=$(jq -c '.' "$MANIFEST" 2>/dev/null || echo '{}')

# Python templating — sed would mangle the JSON.
render_template() {
  local tmpl_path="$1"
  shift
  MY_TMPL="$tmpl_path" python3 - "$@" <<'PY'
import os, sys
tmpl = open(os.environ["MY_TMPL"], "r", encoding="utf-8").read()
args = sys.argv[1:]
for i in range(0, len(args), 2):
    placeholder, value = args[i], args[i + 1]
    tmpl = tmpl.replace(placeholder, value)
sys.stdout.write(tmpl)
PY
}

PROMPT=$(render_template "$PROMPT_TMPL" \
  "<PROJECT_NAME>" "$PROJECT_NAME" \
  "<FORM_FACTOR>" "$FORM_FACTOR" \
  "<SCREEN_NAME>" "$SCREEN_NAME" \
  "<SCREEN_SLUG>" "$SCREEN_SLUG" \
  "<root>" "$ROOT" \
  "<PAGE_PNG>" "$PAGE_PNG" \
  "<OUT_HTML>" "$OUT_HTML" \
  "<STYLE_GUIDE_JSON>" "$STYLE_GUIDE_JSON" \
  "<MANIFEST_JSON>" "$MANIFEST_JSON")

# Remove any prior HTML so the existence check is meaningful.
rm -f "$OUT_HTML"

is_html() {
  [ -f "$1" ] && grep -qi '<!doctype html' "$1" 2>/dev/null && grep -qi '</html>' "$1" 2>/dev/null
}

INITIAL_RESPONSE="$ROOT/.my-harness/codex-html-${FORM_FACTOR}-${SCREEN_SLUG}.md"

echo "=== Generating HTML for $FORM_FACTOR / $SCREEN_SLUG (session: $SESSION_KEY) ==="
bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --context "$PAGE_PNG" "$MANIFEST" \
  --out "$INITIAL_RESPONSE" \
  "$PROMPT"

MAX_RETRY=${HARNESS_GEN_RETRY:-3}
RETRY=0
while ! is_html "$OUT_HTML"; do
  RETRY=$(( RETRY + 1 ))
  if [ "$RETRY" -gt "$MAX_RETRY" ]; then
    echo "::error:: HTML not produced after $MAX_RETRY attempts. Session '$SESSION_KEY' preserved." >&2
    [ -f "$OUT_HTML" ] && echo "::error::   file exists but is not valid HTML — first 200 chars: $(head -c 200 "$OUT_HTML")" >&2
    exit 2
  fi
  NUDGE="HTML file is missing at $OUT_HTML (or is not a complete HTML document — must start with <!DOCTYPE html> and end with </html>). Look at the page PNG attached earlier in this session, then write the complete HTML to that exact path now using your file-write tool. Do NOT paste the HTML body in your text response."
  echo "::warning:: HTML attempt $RETRY/$MAX_RETRY failed; nudging" >&2
  INITIAL_RESPONSE="$ROOT/.my-harness/codex-html-${FORM_FACTOR}-${SCREEN_SLUG}-r${RETRY}.md"
  bash "$HARNESS_DIR/scripts/codex-ask.sh" \
    --role designer \
    --session "$SESSION_KEY" \
    --out "$INITIAL_RESPONSE" \
    "$NUDGE"
done

echo
echo "html:     $OUT_HTML"
echo "session:  $SESSION_KEY"
echo "open:     file://$OUT_HTML"

# Auto-open unless suppressed (gen-page-auto.sh defers opening for batching).
# shellcheck disable=SC1091
. "$HARNESS_DIR/scripts/lib/open-file.sh"
open_file "$OUT_HTML"
