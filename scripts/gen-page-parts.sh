#!/usr/bin/env bash
# gen-page-parts.sh — two-phase image_gen pipeline that produces a page mock
# PNG and its style-matched parts-grid PNG(s) in a SINGLE shared Codex
# session by chaining `image_gen` calls via EDIT mode.
#
# Why edit mode chaining?
#   `image_gen` is stateless across calls. Two `image_gen` invocations with
#   "same style" in their prompts will still produce visually divergent
#   images because the diffusion model has no memory of the prior render.
#   Edit mode flips this: the prior generated image is in the session's
#   conversation context, and the model uses it as the visual reference for
#   the next render. Combined with an explicit style_guide JSON that we
#   echo back as immutable invariants on every parts-grid turn, this is
#   the strongest consistency mechanism Codex supports today.
#
# Per Codex's official $imagegen skill:
#   "Built-in edit mode is for images already visible in the conversation
#    context, such as attached images or images generated earlier in the
#    thread."
#
# Pipeline:
#   Turn 1  → image_gen generate → page-<platform>-<screen>.png
#            + JSON manifest in text response (style_guide + cells)
#   Turn 2  → image_gen EDIT mode against the page → parts-grid-<...>-0.png
#   Turn 3+ → (if image_count > 1) more edit-mode grids: -1.png, -2.png, ...
#
# All turns run on the same session key (design-image-<project-slug>) so
# every screen + platform of this project shares decisions made in turn 1.

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_NAME="${3:?screen name required}"
PROJECT_NAME="${4:?project name required}"

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPL_PAGE="$HARNESS_DIR/prompts/codex-page-mock.md"
TMPL_GRID="$HARNESS_DIR/prompts/codex-parts-grid-edit.md"
[ -f "$TMPL_PAGE" ] || { echo "::error:: $TMPL_PAGE not found" >&2; exit 1; }
[ -f "$TMPL_GRID" ] || { echo "::error:: $TMPL_GRID not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "::error:: jq required" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "::error:: python3 required" >&2; exit 3; }

SCREEN_SLUG=$(printf '%s' "$SCREEN_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | tr ' /' '--' \
  | sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')
SCREEN_SLUG=${SCREEN_SLUG:-screen}

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

# Project-wide image session — every screen / platform / refinement of this
# project shares one Codex thread, so palette / typography / character /
# motif decisions made in turn 1 propagate to every later screen too.
SESSION_KEY="design-image-${PROJECT_SLUG}"
echo "$SESSION_KEY" > "$ROOT/.my-harness/codex-session-design-image.txt"

# Chroma-key color: HARNESS_CHROMA_KEY env > saved file > default #FF00FF.
CHROMA_KEY="${HARNESS_CHROMA_KEY:-#FF00FF}"
printf '%s\n' "$CHROMA_KEY" > "$ROOT/.my-harness/chroma-key.txt"

# Common placeholder substitution — Python keeps JSON safe by not using sed.
render_template() {
  local tmpl_path="$1"
  shift
  local -a kv=("$@")
  MY_TMPL="$tmpl_path" python3 - "${kv[@]}" <<'PY'
import os, sys
tmpl = open(os.environ["MY_TMPL"], "r", encoding="utf-8").read()
args = sys.argv[1:]
for i in range(0, len(args), 2):
    placeholder, value = args[i], args[i + 1]
    tmpl = tmpl.replace(placeholder, value)
sys.stdout.write(tmpl)
PY
}

is_png() { [ -f "$1" ] && file "$1" 2>/dev/null | grep -q "PNG image"; }

# ===== Turn 1: page mock + style_guide manifest =====
PROMPT_PAGE=$(render_template "$TMPL_PAGE" \
  "<PROJECT_NAME>" "$PROJECT_NAME" \
  "<PLATFORM>" "$PLATFORM" \
  "<SCREEN_NAME>" "$SCREEN_NAME" \
  "<SCREEN_SLUG>" "$SCREEN_SLUG" \
  "<root>" "$ROOT")

TURN1_RESPONSE="$ROOT/.my-harness/codex-page-${PLATFORM}-${SCREEN_SLUG}.md"

echo "=== Turn 1: page mock + manifest ==="
bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --context "$ROOT/dev/docs/spec/"*.md \
  --out "$TURN1_RESPONSE" \
  "$PROMPT_PAGE"

# Extract manifest JSON from turn 1 response.
extract_manifest() {
  local file="$1"
  python3 - "$file" <<'PY'
import json, re, sys
body = open(sys.argv[1], "r", encoding="utf-8").read()
for m in re.finditer(r"```json\s*(\{.*?\})\s*```", body, re.DOTALL):
    try:
        obj = json.loads(m.group(1))
        if isinstance(obj, dict) and "image_count" in obj and "style_guide" in obj:
            print(json.dumps(obj, ensure_ascii=False))
            sys.exit(0)
    except json.JSONDecodeError:
        continue
sys.exit(1)
PY
}

# Turn 1 retry loop: nudge for missing PNG or unparseable manifest.
TURN1_MAX_RETRY=${HARNESS_GEN_RETRY:-3}
TURN1_RETRY=0
MANIFEST_JSON=""
while : ; do
  PAGE_OK=0
  is_png "$OUT_PAGE" && PAGE_OK=1
  MANIFEST_JSON=$(extract_manifest "$TURN1_RESPONSE" 2>/dev/null) || MANIFEST_JSON=""

  if [ "$PAGE_OK" -eq 1 ] && [ -n "$MANIFEST_JSON" ]; then
    break
  fi

  TURN1_RETRY=$(( TURN1_RETRY + 1 ))
  if [ "$TURN1_RETRY" -gt "$TURN1_MAX_RETRY" ]; then
    echo "::error:: Turn 1 failed after $TURN1_MAX_RETRY retries (page_ok=$PAGE_OK, manifest=${MANIFEST_JSON:+present}${MANIFEST_JSON:-missing}). Session '$SESSION_KEY' preserved." >&2
    exit 2
  fi

  NUDGE="For the '$SCREEN_NAME' screen on '$PLATFORM' of project '$PROJECT_NAME':  "
  [ "$PAGE_OK" -eq 0 ] && NUDGE="$NUDGE Page PNG missing at $OUT_PAGE — call image_gen and save it.  "
  [ -z "$MANIFEST_JSON" ] && NUDGE="$NUDGE Manifest JSON missing or unparseable — output exactly one \`\`\`json block with the full schema (style_guide, image_count, rows_per_image, cells).  "

  echo "::warning:: Turn 1 attempt $TURN1_RETRY/$TURN1_MAX_RETRY failed; nudging" >&2
  TURN1_RESPONSE="$ROOT/.my-harness/codex-page-${PLATFORM}-${SCREEN_SLUG}-r${TURN1_RETRY}.md"
  bash "$HARNESS_DIR/scripts/codex-ask.sh" \
    --role designer \
    --session "$SESSION_KEY" \
    --out "$TURN1_RESPONSE" \
    "$NUDGE"
done

IMG_COUNT=$(printf '%s' "$MANIFEST_JSON" | jq -r '.image_count')
case "$IMG_COUNT" in ''|*[!0-9]*) echo "::error:: manifest.image_count invalid: '$IMG_COUNT'" >&2; exit 2 ;; esac

# Persist manifest for crop-parts.sh / scaffold scripts.
printf '%s\n' "$MANIFEST_JSON" > "$OUT_MANIFEST"

# Extract the style_guide once — re-injected verbatim into every grid turn
# as the immutable invariants that fight diffusion drift.
STYLE_GUIDE_JSON=$(printf '%s' "$MANIFEST_JSON" | jq -c '.style_guide')

echo "  page:        $OUT_PAGE"
echo "  manifest:    $OUT_MANIFEST"
echo "  image_count: $IMG_COUNT"

# ===== Turn 2..N: each parts-grid via edit mode =====
GRID_MAX_RETRY=${HARNESS_GEN_RETRY:-3}
for (( i=0; i<IMG_COUNT; i++ )); do
  GRID_PATH="${GRID_PREFIX}-${i}.png"
  ROWS=$(printf '%s' "$MANIFEST_JSON" | jq -r ".rows_per_image[$i]")
  CELLS_JSON=$(printf '%s' "$MANIFEST_JSON" | jq -c "[.cells[] | select(.image == $i)]")

  PROMPT_GRID=$(render_template "$TMPL_GRID" \
    "<PROJECT_NAME>" "$PROJECT_NAME" \
    "<PLATFORM>" "$PLATFORM" \
    "<SCREEN_NAME>" "$SCREEN_NAME" \
    "<SCREEN_SLUG>" "$SCREEN_SLUG" \
    "<root>" "$ROOT" \
    "<CHROMA_KEY>" "$CHROMA_KEY" \
    "<IMAGE_INDEX>" "$i" \
    "<IMAGE_COUNT>" "$IMG_COUNT" \
    "<ROWS_IN_THIS_IMAGE>" "$ROWS" \
    "<STYLE_GUIDE_JSON>" "$STYLE_GUIDE_JSON" \
    "<CELLS_JSON>" "$CELLS_JSON")

  echo "=== Turn $((i + 2)): parts-grid $i (edit-mode against page) ==="
  GRID_RESPONSE="$ROOT/.my-harness/codex-grid-${PLATFORM}-${SCREEN_SLUG}-${i}.md"
  bash "$HARNESS_DIR/scripts/codex-ask.sh" \
    --role designer \
    --session "$SESSION_KEY" \
    --out "$GRID_RESPONSE" \
    "$PROMPT_GRID"

  GRID_RETRY=0
  while ! is_png "$GRID_PATH"; do
    GRID_RETRY=$(( GRID_RETRY + 1 ))
    if [ "$GRID_RETRY" -gt "$GRID_MAX_RETRY" ]; then
      echo "::error:: parts-grid $i failed after $GRID_MAX_RETRY retries. Session '$SESSION_KEY' preserved at $ROOT/.my-harness/codex-session-design-image.txt" >&2
      exit 2
    fi
    echo "::warning:: parts-grid $i attempt $GRID_RETRY/$GRID_MAX_RETRY failed; nudging" >&2
    GRID_RESPONSE="$ROOT/.my-harness/codex-grid-${PLATFORM}-${SCREEN_SLUG}-${i}-r${GRID_RETRY}.md"
    NUDGE="Grid PNG missing at $GRID_PATH. Call image_gen in EDIT mode against the page-${PLATFORM}-${SCREEN_SLUG}.png already in this session's context and save the 1024×$((ROWS * 256)) grid to that path. Keep every immutable style invariant from the prior message."
    bash "$HARNESS_DIR/scripts/codex-ask.sh" \
      --role designer \
      --session "$SESSION_KEY" \
      --out "$GRID_RESPONSE" \
      "$NUDGE"
  done

  echo "  grid[$i]:    $GRID_PATH"
done

echo
echo "=== Phase 5 image generation complete ==="
echo "session:  $SESSION_KEY"

# Auto-open every generated PNG so the user can review. Suppress with
# HARNESS_SKIP_OPEN=1 (cross-platform orchestrator sets this to defer
# opening until all platforms finish).
# shellcheck disable=SC1091
. "$HARNESS_DIR/scripts/lib/open-file.sh"
OPEN_LIST=("$OUT_PAGE")
for (( i=0; i<IMG_COUNT; i++ )); do
  OPEN_LIST+=("${GRID_PREFIX}-${i}.png")
done
open_file "${OPEN_LIST[@]}"
