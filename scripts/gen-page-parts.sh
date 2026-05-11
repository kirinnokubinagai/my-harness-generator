#!/usr/bin/env bash
# gen-page-parts.sh — two-phase image_gen pipeline that produces a page mock
# PNG and its style-matched parts-grid PNG(s) in a SINGLE shared Codex
# session by chaining `image_gen` calls via EDIT mode.
#
# Form factor (positional arg #2) is one of:
#   pc      — desktop / laptop viewport (~1280-1440 wide), multi-column
#   mobile  — smartphone viewport (~390 wide), single-column
# Any other string is accepted too (it's just substituted into the prompt
# placeholder), so legacy `web` / `ios` / etc. still work.
#
# Cross-screen and cross-form-factor consistency comes from two mechanisms:
#   (a) The Codex session `design-image-<project-slug>` keeps every prior
#       image in conversation context, so edit mode can reference it.
#   (b) The first generated artifact's `style_guide` JSON is persisted to
#       its manifest.json. Every subsequent gen-page-parts.sh invocation
#       (same project, different screen OR form factor) finds that prior
#       style_guide and injects it into the Turn-1 prompt as IMMUTABLE
#       INVARIANTS. Codex echoes the invariants back into its own manifest
#       so the chain stays consistent even across separate invocations.
#
# Pipeline (per gen-page-parts.sh run):
#   Turn 1  → image_gen generate → page-<form-factor>-<screen>.png
#            + JSON manifest in text response (style_guide + cells)
#   Turn 2  → image_gen EDIT mode against the page → parts-grid-<...>-0.png
#   Turn 3+ → (if image_count > 1) more edit-mode grids: -1.png, -2.png, ...

set -u

ROOT="${1:?root required}"
FORM_FACTOR="${2:?form-factor required (pc|mobile|...)}"
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
         "$ROOT/dev/public/design/parts/${FORM_FACTOR}/${SCREEN_SLUG}" \
         "$ROOT/.my-harness"

OUT_PAGE="$ROOT/dev/docs/design/page-${FORM_FACTOR}-${SCREEN_SLUG}.png"
OUT_MANIFEST="$ROOT/dev/public/design/parts/${FORM_FACTOR}/${SCREEN_SLUG}/manifest.json"
GRID_PREFIX="$ROOT/dev/docs/design/parts-grid-${FORM_FACTOR}-${SCREEN_SLUG}"

# Project-wide image session — every screen / form-factor / refinement of
# this project shares one Codex thread, so palette / typography / character /
# motif decisions made on the FIRST artifact propagate to every later screen
# AND every later form factor automatically (both via session context and
# via the prior_style_guide echo mechanism below).
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

# ===== Discover prior style_guide (project-wide invariants) =====
# Search every manifest.json under this project for a style_guide field.
# First one wins (oldest by find's default order is fine — they should all
# be echoes of the same invariants anyway). Exclude the current target so
# a stale prior run doesn't shadow itself if user is regenerating.
#
# When found  → inject as IMMUTABLE INVARIANTS into the Turn-1 prompt.
# When absent → Codex decides style_guide freely (this is the first artifact).
PRIOR_STYLE_GUIDE=""
# Clear the current manifest if it exists so it doesn't shadow itself.
rm -f "$OUT_MANIFEST"
while IFS= read -r m; do
  sg=$(jq -c '.style_guide // empty' "$m" 2>/dev/null || true)
  if [ -n "$sg" ] && [ "$sg" != "null" ] && [ "$sg" != "" ]; then
    PRIOR_STYLE_GUIDE="$sg"
    echo "[gen-page-parts] inheriting style_guide from $m" >&2
    break
  fi
done < <(find "$ROOT/dev/public/design/parts" -name 'manifest.json' -type f 2>/dev/null | sort)

if [ -n "$PRIOR_STYLE_GUIDE" ]; then
  PRIOR_BLOCK=$(printf '## LOCKED-IN PROJECT INVARIANTS (no creative deviation)\n\nThe project'\''s visual identity was established in an earlier turn. **You MUST honor these EXACTLY here — no new colors, no shift in illustration style, no new character design, no new motifs.** Drift = failure.\n\n```json\n%s\n```\n\nWhen Codex inherits these invariants while moving to a NEW form factor (e.g. pc → mobile or mobile → pc): keep palette / illustration_style / line_weight / character_design / decorative_motifs IDENTICAL, but reinvent layout, spacing, type scale, and CTA placement to suit the new form factor. A PC mock shrunk into a mobile viewport is wrong; a mobile mock blown up into a PC viewport is wrong. Layout is the ONE thing you'\''re allowed to change.\n' "$PRIOR_STYLE_GUIDE")
else
  PRIOR_BLOCK=$'## STYLE DECISIONS (this is the FIRST artifact for the project — you set the tone)\n\nThere are no prior invariants. Every visual choice you make here — palette (every hex), illustration_style, line_weight, character_design, decorative_motifs — becomes the project\'s locked-in style_guide that every later screen AND every later form factor must honor.\n\nBe deliberate: pick choices that will work for BOTH form factors (pc AND mobile) since both will share these invariants. Avoid pc-only or mobile-only tropes unless the brand genuinely demands them.\n'
fi

# ===== Turn 1: page mock + style_guide manifest =====
PROMPT_PAGE=$(render_template "$TMPL_PAGE" \
  "<PROJECT_NAME>" "$PROJECT_NAME" \
  "<FORM_FACTOR>" "$FORM_FACTOR" \
  "<SCREEN_NAME>" "$SCREEN_NAME" \
  "<SCREEN_SLUG>" "$SCREEN_SLUG" \
  "<root>" "$ROOT" \
  "<PRIOR_STYLE_GUIDE_BLOCK>" "$PRIOR_BLOCK")

TURN1_RESPONSE="$ROOT/.my-harness/codex-page-${FORM_FACTOR}-${SCREEN_SLUG}.md"

echo "=== Turn 1: page mock + manifest ($FORM_FACTOR / $SCREEN_NAME) ==="
bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --context "$ROOT/dev/docs/spec/"*.md \
  --out "$TURN1_RESPONSE" \
  "$PROMPT_PAGE"

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

# Turn 1 retry loop.
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

  NUDGE="For the '$SCREEN_NAME' screen on '$FORM_FACTOR' form factor of project '$PROJECT_NAME':  "
  [ "$PAGE_OK" -eq 0 ] && NUDGE="$NUDGE Page PNG missing at $OUT_PAGE — call image_gen and save it.  "
  [ -z "$MANIFEST_JSON" ] && NUDGE="$NUDGE Manifest JSON missing or unparseable — output exactly one \`\`\`json block with the full schema (style_guide, image_count, rows_per_image, cells).  "

  echo "::warning:: Turn 1 attempt $TURN1_RETRY/$TURN1_MAX_RETRY failed; nudging" >&2
  TURN1_RESPONSE="$ROOT/.my-harness/codex-page-${FORM_FACTOR}-${SCREEN_SLUG}-r${TURN1_RETRY}.md"
  bash "$HARNESS_DIR/scripts/codex-ask.sh" \
    --role designer \
    --session "$SESSION_KEY" \
    --out "$TURN1_RESPONSE" \
    "$NUDGE"
done

IMG_COUNT=$(printf '%s' "$MANIFEST_JSON" | jq -r '.image_count')
case "$IMG_COUNT" in ''|*[!0-9]*) echo "::error:: manifest.image_count invalid: '$IMG_COUNT'" >&2; exit 2 ;; esac

printf '%s\n' "$MANIFEST_JSON" > "$OUT_MANIFEST"
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
    "<FORM_FACTOR>" "$FORM_FACTOR" \
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
  GRID_RESPONSE="$ROOT/.my-harness/codex-grid-${FORM_FACTOR}-${SCREEN_SLUG}-${i}.md"
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
    GRID_RESPONSE="$ROOT/.my-harness/codex-grid-${FORM_FACTOR}-${SCREEN_SLUG}-${i}-r${GRID_RETRY}.md"
    NUDGE="Grid PNG missing at $GRID_PATH. Call image_gen in EDIT mode against the page-${FORM_FACTOR}-${SCREEN_SLUG}.png already in this session's context and save the 1024×$((ROWS * 256)) grid to that path. Keep every immutable style invariant from the prior message."
    bash "$HARNESS_DIR/scripts/codex-ask.sh" \
      --role designer \
      --session "$SESSION_KEY" \
      --out "$GRID_RESPONSE" \
      "$NUDGE"
  done

  echo "  grid[$i]:    $GRID_PATH"
done

echo
echo "=== gen-page-parts complete ($FORM_FACTOR / $SCREEN_NAME) ==="
echo "session:  $SESSION_KEY"

# Auto-open every generated PNG. Suppress with HARNESS_SKIP_OPEN=1 (used by
# gen-page-auto.sh to defer opening until ALL form factors finish).
# shellcheck disable=SC1091
. "$HARNESS_DIR/scripts/lib/open-file.sh"
OPEN_LIST=("$OUT_PAGE")
for (( i=0; i<IMG_COUNT; i++ )); do
  OPEN_LIST+=("${GRID_PREFIX}-${i}.png")
done
open_file "${OPEN_LIST[@]}"
