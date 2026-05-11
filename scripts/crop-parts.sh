#!/usr/bin/env bash
# crop-parts.sh — slice the parts-grid PNG into transparent-background per-part
# PNGs using ImageMagick. Cell size is FIXED at 256×256 (override via env
# CELL_SIZE), so cropping is fully deterministic — no Claude Vision required.
#
# The parts-grid image (produced by gen-page-parts.sh) has known dimensions:
#   width  = 1024
#   height = manifest.rows × 256
# Columns are 4. Each cell is 256×256 (or CELL_SIZE).
#
# Outputs:
#   <root>/dev/public/design/parts/<platform>/<screen-slug>/<name>.png         transparent PNG asset
#   <root>/dev/public/design/parts/<platform>/<screen-slug>/manifest.json      (already there from gen-page-parts.sh)
#   <root>/dev/src/components/design/<platform>/<screen-slug>/parts.ts         TS import map
#
# Requires: ImageMagick (magick or convert) + jq.
#
# Usage:
#   bash scripts/crop-parts.sh <root> <platform> <screen-slug>
#
# Manifest path is inferred:
#   <root>/dev/public/design/parts/<platform>/<screen-slug>/manifest.json

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_SLUG="${3:?screen-slug required}"
CELL_SIZE="${CELL_SIZE:-256}"

IN_GRID="$ROOT/dev/docs/design/parts-grid-${PLATFORM}-${SCREEN_SLUG}.png"
ASSET_DIR="$ROOT/dev/public/design/parts/${PLATFORM}/${SCREEN_SLUG}"
TS_DIR="$ROOT/dev/src/components/design/${PLATFORM}/${SCREEN_SLUG}"
MANIFEST="$ASSET_DIR/manifest.json"

[ -f "$MANIFEST" ] || { echo "::error:: not found: $MANIFEST (run gen-page-parts.sh first)" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "::error:: jq required" >&2; exit 3; }
if command -v magick >/dev/null 2>&1; then IM="magick"
elif command -v convert >/dev/null 2>&1; then IM="convert"
else echo "::error:: ImageMagick required (brew install imagemagick / apt install imagemagick)" >&2; exit 3
fi

ROWS=$(jq -r .rows "$MANIFEST")
case "$ROWS" in ''|*[!0-9]*) echo "::error:: manifest.rows invalid: '$ROWS'" >&2; exit 1 ;; esac

# Zero-asset case: nothing to crop. Still create an empty parts.ts so imports work.
if [ "$ROWS" = "0" ]; then
  mkdir -p "$TS_DIR"
  {
    printf '/** Auto-generated empty parts map for %s / %s (no non-HTML assets). */\n' "$PLATFORM" "$SCREEN_SLUG"
    printf 'export const parts = {} as const;\n'
    printf 'export type PartKey = keyof typeof parts;\n'
  } > "$TS_DIR/parts.ts"
  echo "no assets to crop. wrote empty parts map."
  exit 0
fi

[ -f "$IN_GRID" ] || { echo "::error:: not found: $IN_GRID (gen-page-parts.sh should have produced it when rows > 0)" >&2; exit 1; }

read -r IMG_W IMG_H < <($IM identify -format "%w %h" "$IN_GRID")
[ -n "${IMG_W:-}" ] && [ -n "${IMG_H:-}" ] || { echo "::error:: can't read grid dimensions" >&2; exit 1; }

# Width sanity: should be 4 × CELL_SIZE (default 1024). Tolerate small deviation.
EXPECTED_W=$(( CELL_SIZE * 4 ))
if [ "$IMG_W" -lt $(( EXPECTED_W - 16 )) ] || [ "$IMG_W" -gt $(( EXPECTED_W + 16 )) ]; then
  echo "::warning:: parts-grid width is $IMG_W, expected ~$EXPECTED_W (4 × CELL_SIZE=$CELL_SIZE). Cropping may misalign." >&2
fi

mkdir -p "$ASSET_DIR" "$TS_DIR"

PARTS_TS="$TS_DIR/parts.ts"
{
  printf '/**\n'
  printf ' * 概要: %s / %s 画面の design parts asset 一覧。\n' "$PLATFORM" "$SCREEN_SLUG"
  printf ' *       gen-page-parts.sh + crop-parts.sh が自動生成する。手で編集しない。\n'
  printf ' *       実装側は `import { parts } from "./parts"` で各 PNG の絶対パスを取得できる。\n'
  printf ' */\n\n'
  printf 'export const parts = {\n'
} > "$PARTS_TS"

camel_case() {
  printf '%s' "$1" | awk -F'-' '{
    out=""
    for (i=1; i<=NF; i++) {
      w = $i
      if (i == 1) { out = tolower(w) }
      else { out = out toupper(substr(w,1,1)) tolower(substr(w,2)) }
    }
    print out
  }'
}

jq -c '.cells[]' "$MANIFEST" | while read -r CELL; do
  R=$(jq -r .row  <<<"$CELL")
  C=$(jq -r .col  <<<"$CELL")
  N=$(jq -r .name <<<"$CELL")
  case "$R$C" in ''|*[!0-9]*) echo "::warning:: bad cell row=$R col=$C, skip" >&2; continue ;; esac

  X=$(( CELL_SIZE * C ))
  Y=$(( CELL_SIZE * R ))
  OUT="$ASSET_DIR/${N}.png"

  $IM "$IN_GRID" \
    -crop "${CELL_SIZE}x${CELL_SIZE}+${X}+${Y}" +repage \
    -alpha set -fuzz 5% \
    -fill none \
    -draw "alpha 0,0 floodfill" \
    -draw "alpha $((CELL_SIZE-1)),0 floodfill" \
    -draw "alpha 0,$((CELL_SIZE-1)) floodfill" \
    -draw "alpha $((CELL_SIZE-1)),$((CELL_SIZE-1)) floodfill" \
    -strip \
    "$OUT"

  KEY=$(camel_case "$N")
  REL_PATH="/design/parts/${PLATFORM}/${SCREEN_SLUG}/${N}.png"
  printf '  %s: %s,\n' "$KEY" "'$REL_PATH'" >> "$PARTS_TS"
  echo "  cropped: $OUT  (${CELL_SIZE}×${CELL_SIZE} @ ${X},${Y})"
done

printf '} as const;\n\nexport type PartKey = keyof typeof parts;\n' >> "$PARTS_TS"

echo
echo "assets:   $ASSET_DIR"
echo "parts.ts: $PARTS_TS"
