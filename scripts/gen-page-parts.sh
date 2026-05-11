#!/usr/bin/env bash
# gen-page-parts.sh — fully-automated page mock + PNG assets grid generation.
#
# One Codex call. Codex produces:
#   1. dev/docs/design/page-<platform>-<screen-slug>.png       (full page mock)
#   2. dev/docs/design/parts-grid-<platform>-<screen-slug>.png (256×256 cells, 4 cols × N rows)
#   3. JSON manifest in its text response (cell positions + kebab-case names)
#
# This script:
#   - Pins a deterministic --session per (platform, screen-slug). Refinement + retries
#     reuse it.
#   - Calls codex-ask.sh once, captures the response text.
#   - Verifies both PNGs exist and are real PNGs (file(1) check).
#   - Extracts the manifest JSON from the response and saves to
#     dev/public/design/parts/<platform>/<screen-slug>/manifest.json
#   - On failure, retries in the same session with explicit follow-up nudges
#     (up to MAX_RETRY = 3, override via HARNESS_GEN_RETRY).
#
# Caller (my-harness-init Phase 5) must already have asked the user
# "Codex でこのページのデザインを作りますか?" and received yes.
#
# Usage:
#   bash scripts/gen-page-parts.sh <root> <platform> <screen-name> <project-name>

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_NAME="${3:?screen name required}"
PROJECT_NAME="${4:?project name required}"

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_TMPL="$HARNESS_DIR/prompts/codex-page-and-parts.md"
[ -f "$PROMPT_TMPL" ] || { echo "::error:: $PROMPT_TMPL not found" >&2; exit 1; }

# slug from screen name
SCREEN_SLUG=$(printf '%s' "$SCREEN_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | tr ' /' '--' \
  | sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')
SCREEN_SLUG=${SCREEN_SLUG:-screen}

mkdir -p "$ROOT/dev/docs/design" \
         "$ROOT/dev/public/design/parts/${PLATFORM}/${SCREEN_SLUG}"

OUT_PAGE="$ROOT/dev/docs/design/page-${PLATFORM}-${SCREEN_SLUG}.png"
OUT_GRID="$ROOT/dev/docs/design/parts-grid-${PLATFORM}-${SCREEN_SLUG}.png"
OUT_MANIFEST="$ROOT/dev/public/design/parts/${PLATFORM}/${SCREEN_SLUG}/manifest.json"

# Deterministic session key
SESSION_KEY="design-page-${PLATFORM}-${SCREEN_SLUG}"
echo "$SESSION_KEY" > "$ROOT/.my-harness/codex-session-design-${PLATFORM}-${SCREEN_SLUG}.txt"

# Fill placeholders in prompt
PROMPT=$(sed \
  -e "s|<PROJECT_NAME>|$PROJECT_NAME|g" \
  -e "s|<PLATFORM>|$PLATFORM|g" \
  -e "s|<SCREEN_NAME>|$SCREEN_NAME|g" \
  -e "s|<SCREEN_SLUG>|$SCREEN_SLUG|g" \
  -e "s|<root>|$ROOT|g" \
  "$PROMPT_TMPL")

# Extract a JSON object from a markdown text. Returns the first valid
# {"rows": ..., "cells": [...]} block; empty on failure.
extract_manifest() {
  local file="$1"
  [ -f "$file" ] || return 1
  python3 - "$file" <<'PY'
import json, re, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    body = f.read()
# Try fenced json blocks first
for m in re.finditer(r'```json\s*(\{.*?\})\s*```', body, re.DOTALL):
    try:
        obj = json.loads(m.group(1))
        if isinstance(obj, dict) and 'rows' in obj and 'cells' in obj:
            print(json.dumps(obj, ensure_ascii=False))
            sys.exit(0)
    except json.JSONDecodeError:
        continue
# Fallback: any standalone JSON object with rows + cells
for m in re.finditer(r'\{[^{}]*"rows"\s*:[^{}]*"cells"\s*:.*?\}', body, re.DOTALL):
    try:
        obj = json.loads(m.group(0))
        if 'rows' in obj and 'cells' in obj:
            print(json.dumps(obj, ensure_ascii=False))
            sys.exit(0)
    except json.JSONDecodeError:
        continue
sys.exit(1)
PY
}

is_png() {
  [ -f "$1" ] && file "$1" 2>/dev/null | grep -q "PNG image"
}

INITIAL_RESPONSE="$ROOT/.my-harness/codex-page-${PLATFORM}-${SCREEN_SLUG}.md"

bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --context "$ROOT/dev/docs/spec/"*.md \
  --out "$INITIAL_RESPONSE" \
  "$PROMPT"

MAX_RETRY=${HARNESS_GEN_RETRY:-3}
RETRY=0

# Loop until: page PNG ok AND (grid PNG ok OR manifest says rows=0)
while : ; do
  PAGE_OK=0
  GRID_OK=0
  MANIFEST_JSON=""

  is_png "$OUT_PAGE" && PAGE_OK=1
  is_png "$OUT_GRID" && GRID_OK=1

  if MANIFEST_JSON=$(extract_manifest "$INITIAL_RESPONSE"); then
    ROWS=$(printf '%s' "$MANIFEST_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("rows",0))')
  else
    ROWS=""
  fi

  # Success conditions:
  #   - page exists
  #   - manifest extracted
  #   - if rows > 0, grid must also exist
  if [ "$PAGE_OK" -eq 1 ] && [ -n "$ROWS" ]; then
    if [ "$ROWS" = "0" ] || [ "$GRID_OK" -eq 1 ]; then
      break
    fi
  fi

  RETRY=$(( RETRY + 1 ))
  if [ "$RETRY" -gt "$MAX_RETRY" ]; then
    echo "::error:: Failed after $MAX_RETRY retries. Session '$SESSION_KEY' preserved." >&2
    echo "::error::   page PNG ok: $PAGE_OK  grid PNG ok: $GRID_OK  manifest rows: '${ROWS:-<missing>}'" >&2
    exit 2
  fi

  NUDGE=""
  [ "$PAGE_OK" -eq 0 ] && NUDGE="$NUDGE Page PNG missing at $OUT_PAGE. Call image_gen and save it now.  "
  [ -n "$ROWS" ] && [ "$ROWS" != "0" ] && [ "$GRID_OK" -eq 0 ] && \
    NUDGE="$NUDGE Parts-grid PNG missing at $OUT_GRID. Call image_gen and save it now (4 columns × $ROWS rows × 256×256 cells, white background).  "
  [ -z "$ROWS" ] && \
    NUDGE="$NUDGE Manifest JSON missing or unparseable. Output a single fenced \`\`\`json ... \`\`\` block with { rows, cells: [{row, col, name}] }.  "

  echo "::warning:: attempt $RETRY/$MAX_RETRY failed; following up: $NUDGE" >&2

  INITIAL_RESPONSE="$ROOT/.my-harness/codex-page-${PLATFORM}-${SCREEN_SLUG}-r${RETRY}.md"
  bash "$HARNESS_DIR/scripts/codex-ask.sh" \
    --role designer \
    --session "$SESSION_KEY" \
    --out "$INITIAL_RESPONSE" \
    "$NUDGE"
done

# Save manifest
printf '%s\n' "$MANIFEST_JSON" > "$OUT_MANIFEST"
echo
echo "page:     $OUT_PAGE"
echo "grid:     $OUT_GRID"
echo "manifest: $OUT_MANIFEST  (rows=$ROWS)"
echo "session:  $SESSION_KEY"
