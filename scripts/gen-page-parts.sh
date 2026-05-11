#!/usr/bin/env bash
# gen-page-parts.sh — fully-automated page mock + (zero, one, or many) parts-grid
# PNGs. Single Codex call. Codex emits:
#   1. dev/docs/design/page-<platform>-<screen-slug>.png            (always)
#   2. dev/docs/design/parts-grid-<platform>-<screen-slug>-<N>.png  (0..image_count-1)
#   3. JSON manifest in its text response (image_count, rows_per_image[], cells[])
#
# Cell size is 256×256, 4 columns, up to 7 rows per grid image (gpt-image-2
# size cap). If a screen needs more than 28 non-HTML assets, Codex paginates
# into multiple grid images automatically.
#
# Retries (3× by default) in the same Codex session if any expected output
# is missing.

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_NAME="${3:?screen name required}"
PROJECT_NAME="${4:?project name required}"

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_TMPL="$HARNESS_DIR/prompts/codex-page-and-parts.md"
[ -f "$PROMPT_TMPL" ] || { echo "::error:: $PROMPT_TMPL not found" >&2; exit 1; }

SCREEN_SLUG=$(printf '%s' "$SCREEN_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | tr ' /' '--' \
  | sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')
SCREEN_SLUG=${SCREEN_SLUG:-screen}

# Project-wide slug — used for the Codex session key so that ALL screens
# across ALL platforms in this project share one Codex thread. This is
# how design decisions (palette, typography, icon language, brand voice,
# button rounding) propagate from the first screen to every later one.
PROJECT_SLUG=$(printf '%s' "$PROJECT_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')
PROJECT_SLUG=${PROJECT_SLUG:-project}

mkdir -p "$ROOT/dev/docs/design" \
         "$ROOT/dev/public/design/parts/${PLATFORM}/${SCREEN_SLUG}" \
         "$ROOT/.my-harness"

OUT_PAGE="$ROOT/dev/docs/design/page-${PLATFORM}-${SCREEN_SLUG}.png"
OUT_MANIFEST="$ROOT/dev/public/design/parts/${PLATFORM}/${SCREEN_SLUG}/manifest.json"
GRID_PREFIX="$ROOT/dev/docs/design/parts-grid-${PLATFORM}-${SCREEN_SLUG}"

# One Codex image-generation session per project — NOT per screen, NOT per
# platform. The session accumulates every prior decision in the same thread,
# so when generating the 2nd screen Codex already knows the palette / icon
# style / brand language it established for the 1st. To refine a specific
# screen later, name the screen explicitly in your prompt ("update the Login
# screen's hero illustration") since the session contains multiple screens.
SESSION_KEY="design-image-${PROJECT_SLUG}"
echo "$SESSION_KEY" > "$ROOT/.my-harness/codex-session-design-image.txt"

PROMPT=$(sed \
  -e "s|<PROJECT_NAME>|$PROJECT_NAME|g" \
  -e "s|<PLATFORM>|$PLATFORM|g" \
  -e "s|<SCREEN_NAME>|$SCREEN_NAME|g" \
  -e "s|<SCREEN_SLUG>|$SCREEN_SLUG|g" \
  -e "s|<root>|$ROOT|g" \
  "$PROMPT_TMPL")

extract_manifest() {
  local file="$1"
  [ -f "$file" ] || return 1
  python3 - "$file" <<'PY'
import json, re, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    body = f.read()
for m in re.finditer(r'```json\s*(\{.*?\})\s*```', body, re.DOTALL):
    try:
        obj = json.loads(m.group(1))
        if isinstance(obj, dict) and 'image_count' in obj and 'cells' in obj:
            print(json.dumps(obj, ensure_ascii=False))
            sys.exit(0)
    except json.JSONDecodeError:
        continue
for m in re.finditer(r'\{[^{}]*"image_count"\s*:[^{}]*"cells"\s*:.*?\}', body, re.DOTALL):
    try:
        obj = json.loads(m.group(0))
        if 'image_count' in obj and 'cells' in obj:
            print(json.dumps(obj, ensure_ascii=False))
            sys.exit(0)
    except json.JSONDecodeError:
        continue
sys.exit(1)
PY
}

is_png() { [ -f "$1" ] && file "$1" 2>/dev/null | grep -q "PNG image"; }

INITIAL_RESPONSE="$ROOT/.my-harness/codex-page-${PLATFORM}-${SCREEN_SLUG}.md"

bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --context "$ROOT/dev/docs/spec/"*.md \
  --out "$INITIAL_RESPONSE" \
  "$PROMPT"

MAX_RETRY=${HARNESS_GEN_RETRY:-3}
RETRY=0

while : ; do
  PAGE_OK=0
  is_png "$OUT_PAGE" && PAGE_OK=1

  MANIFEST_JSON=""
  MANIFEST_JSON=$(extract_manifest "$INITIAL_RESPONSE" 2>/dev/null) || MANIFEST_JSON=""

  IMG_COUNT=""
  MISSING_GRIDS=""
  if [ -n "$MANIFEST_JSON" ]; then
    IMG_COUNT=$(printf '%s' "$MANIFEST_JSON" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("image_count", 0))')
    case "$IMG_COUNT" in
      ''|*[!0-9]*) IMG_COUNT="" ;;
    esac
  fi

  if [ -n "$IMG_COUNT" ] && [ "$IMG_COUNT" -gt 0 ]; then
    for ((i=0; i<IMG_COUNT; i++)); do
      P="${GRID_PREFIX}-${i}.png"
      if ! is_png "$P"; then
        MISSING_GRIDS="${MISSING_GRIDS}${P} "
      fi
    done
  fi

  # Success: page PNG ok, manifest parsed, every declared grid image present.
  if [ "$PAGE_OK" -eq 1 ] && [ -n "$IMG_COUNT" ] && [ -z "$MISSING_GRIDS" ]; then
    break
  fi

  RETRY=$(( RETRY + 1 ))
  if [ "$RETRY" -gt "$MAX_RETRY" ]; then
    echo "::error:: Failed after $MAX_RETRY retries. Session '$SESSION_KEY' preserved." >&2
    echo "::error::   page PNG ok: $PAGE_OK  image_count: '${IMG_COUNT:-<missing>}'  missing grids: '${MISSING_GRIDS:-none}'" >&2
    exit 2
  fi

  # Project-wide session contains multiple screens — always name the target
  # screen explicitly in retry prompts so Codex doesn't regenerate the wrong one.
  NUDGE="For the '$SCREEN_NAME' screen on '$PLATFORM' of project '$PROJECT_NAME':  "
  [ "$PAGE_OK" -eq 0 ] && NUDGE="$NUDGE Page PNG missing at $OUT_PAGE. Call image_gen and save it now.  "
  [ -z "$IMG_COUNT" ] && \
    NUDGE="$NUDGE Manifest JSON missing or unparseable. Output exactly one fenced \`\`\`json block with {image_count, rows_per_image, cells:[{image,row,col,name}]}.  "
  if [ -n "$MISSING_GRIDS" ]; then
    NUDGE="$NUDGE Missing grid image(s): $MISSING_GRIDS — call image_gen for each one (4 cols, 256×256 cells, ≤7 rows per image, solid magenta #FF00FF background per the original prompt).  "
  fi

  echo "::warning:: attempt $RETRY/$MAX_RETRY failed; following up: $NUDGE" >&2

  INITIAL_RESPONSE="$ROOT/.my-harness/codex-page-${PLATFORM}-${SCREEN_SLUG}-r${RETRY}.md"
  bash "$HARNESS_DIR/scripts/codex-ask.sh" \
    --role designer \
    --session "$SESSION_KEY" \
    --out "$INITIAL_RESPONSE" \
    "$NUDGE"
done

printf '%s\n' "$MANIFEST_JSON" > "$OUT_MANIFEST"
echo
echo "page:     $OUT_PAGE"
if [ "$IMG_COUNT" -gt 0 ]; then
  for ((i=0; i<IMG_COUNT; i++)); do
    echo "grid[$i]:  ${GRID_PREFIX}-${i}.png"
  done
else
  echo "grids:    none (no non-HTML assets on this screen)"
fi
echo "manifest: $OUT_MANIFEST"
echo "session:  $SESSION_KEY"

# Auto-open the page mock + every grid image for the user to review.
# Suppress with HARNESS_SKIP_OPEN=1 (used by gen-page-cross-platform.sh
# so it can open all platforms' outputs together at the end).
# shellcheck disable=SC1091
. "$HARNESS_DIR/scripts/lib/open-file.sh"
OPEN_LIST=("$OUT_PAGE")
for ((i=0; i<IMG_COUNT; i++)); do
  OPEN_LIST+=("${GRID_PREFIX}-${i}.png")
done
open_file "${OPEN_LIST[@]}"
