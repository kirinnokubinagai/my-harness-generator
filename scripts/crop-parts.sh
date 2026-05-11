#!/usr/bin/env bash
# crop-parts.sh — slice the bottom-35 % parts grid of a page+parts image
# into transparent-background PNGs that are usable as runtime assets,
# and emit a TypeScript manifest so components can import the asset paths.
#
# Layout (from gen-page-parts.sh + Codex):
#   y = 0      .. 0.65 × H : full page mock (untouched)
#   y = 0.65 H .. H        : parts grid, 4 columns × N rows, white background
#
# Caller passes a manifest.json (produced by Claude via Vision on the bottom
# 35 %) listing each cell's row / col / name. Cropping is deterministic from
# the manifest; transparency is produced by flood-fill from the 4 corners of
# each cropped cell (preserves any white pixels INSIDE the component).
#
# Usage:
#   bash scripts/crop-parts.sh <root> <platform> <screen-slug> <manifest.json>
#
# Outputs:
#   <root>/dev/public/design/parts/<platform>/<screen-slug>/<name>.png    (transparent PNG asset)
#   <root>/dev/public/design/parts/<platform>/<screen-slug>/manifest.json (copy)
#   <root>/dev/src/components/design/<platform>/<screen-slug>/parts.ts    (TS path manifest)
#
# Requires: ImageMagick (magick or convert) + jq.

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_SLUG="${3:?screen-slug required}"
MANIFEST="${4:?manifest.json required}"

IN_PNG="$ROOT/dev/docs/design/page-${PLATFORM}-${SCREEN_SLUG}.png"
[ -f "$IN_PNG" ]   || { echo "::error:: not found: $IN_PNG" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "::error:: not found: $MANIFEST" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "::error:: jq required" >&2; exit 3; }
if command -v magick >/dev/null 2>&1; then IM="magick"
elif command -v convert >/dev/null 2>&1; then IM="convert"
else echo "::error:: ImageMagick required (brew install imagemagick / apt install imagemagick)" >&2; exit 3
fi

# Image dimensions.
read -r IMG_W IMG_H < <($IM identify -format "%w %h" "$IN_PNG")
[ -n "${IMG_W:-}" ] && [ -n "${IMG_H:-}" ] || { echo "::error:: can't read $IN_PNG dimensions" >&2; exit 1; }

GRID_TOP=$(( IMG_H * 65 / 100 ))
GRID_H=$(( IMG_H - GRID_TOP ))

ROWS=$(jq -r .rows "$MANIFEST")
case "$ROWS" in ''|*[!0-9]*|0) echo "::error:: rows must be positive int (got: $ROWS)" >&2; exit 1 ;; esac

CELL_W=$(( IMG_W / 4 ))
CELL_H=$(( GRID_H / ROWS ))

ASSET_DIR="$ROOT/dev/public/design/parts/${PLATFORM}/${SCREEN_SLUG}"
TS_DIR="$ROOT/dev/src/components/design/${PLATFORM}/${SCREEN_SLUG}"
mkdir -p "$ASSET_DIR" "$TS_DIR"
cp "$MANIFEST" "$ASSET_DIR/manifest.json"

PARTS_TS="$TS_DIR/parts.ts"
{
  printf '/**\n'
  printf ' * 概要: %s / %s 画面の design parts asset 一覧。\n' "$PLATFORM" "$SCREEN_SLUG"
  printf ' *       gen-page-parts.sh + crop-parts.sh が自動生成する。手で編集しない。\n'
  printf ' *       実装側は `import { parts } from "./parts"` で各 PNG の絶対パスを取得できる。\n'
  printf ' */\n\n'
  printf 'export const parts = {\n'
} > "$PARTS_TS"

# Tolerate "fuzz" not being supported in old IM; we'll fall back to plain crop without transparency.
FUZZ_OPT="-fuzz 5%"
if ! $IM -list option 2>/dev/null | grep -q fuzz; then FUZZ_OPT=""; fi

camel_case() {
  printf '%s' "$1" | awk -F'-' '{
    out=""
    for (i=1; i<=NF; i++) {
      w = $i
      if (i == 1) {
        out = tolower(w)
      } else {
        out = out toupper(substr(w,1,1)) tolower(substr(w,2))
      }
    }
    print out
  }'
}

jq -c '.cells[]' "$MANIFEST" | while read -r CELL; do
  R=$(jq -r .row  <<<"$CELL")
  C=$(jq -r .col  <<<"$CELL")
  N=$(jq -r .name <<<"$CELL")
  case "$R$C" in ''|*[!0-9]*) echo "::warning:: bad cell row=$R col=$C, skip" >&2; continue ;; esac

  X=$(( CELL_W * C ))
  Y=$(( GRID_TOP + CELL_H * R ))
  OUT="$ASSET_DIR/${N}.png"

  # Crop the cell, then flood-fill from all 4 corners with transparent to
  # remove the white background while preserving any white pixels INSIDE
  # the component (because they're not connected to a corner).
  $IM "$IN_PNG" \
    -crop "${CELL_W}x${CELL_H}+${X}+${Y}" +repage \
    -alpha set $FUZZ_OPT \
    -fill none \
    -draw "alpha 0,0 floodfill" \
    -draw "alpha $((CELL_W-1)),0 floodfill" \
    -draw "alpha 0,$((CELL_H-1)) floodfill" \
    -draw "alpha $((CELL_W-1)),$((CELL_H-1)) floodfill" \
    -strip \
    "$OUT"

  KEY=$(camel_case "$N")
  REL_PATH="/design/parts/${PLATFORM}/${SCREEN_SLUG}/${N}.png"
  printf '  %s: %s,\n' "$KEY" "'$REL_PATH'" >> "$PARTS_TS"
  echo "  cropped: $OUT"
done

printf '} as const;\n\nexport type PartKey = keyof typeof parts;\n' >> "$PARTS_TS"

echo
echo "assets: $ASSET_DIR"
echo "ts:     $PARTS_TS"
