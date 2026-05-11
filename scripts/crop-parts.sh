#!/usr/bin/env bash
# crop-parts.sh — slice every parts-grid PNG into transparent-background
# per-part PNGs. Supports manifests that span MULTIPLE grid images:
# each cell has an `image` index pointing at the right
# parts-grid-<platform>-<screen-slug>-<image>.png to source from.
#
# Cell size is FIXED at 256×256 (override via env CELL_SIZE). Cropping is
# fully deterministic from manifest indices — no Vision required.
#
# Outputs:
#   <root>/dev/public/design/parts/<platform>/<screen-slug>/<name>.png      transparent PNG asset
#   <root>/dev/src/components/design/<platform>/<screen-slug>/parts.ts      TS import map
#
# Requires: ImageMagick (magick or convert) + jq.

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_SLUG="${3:?screen-slug required}"
CELL_SIZE="${CELL_SIZE:-256}"

GRID_PREFIX="$ROOT/dev/docs/design/parts-grid-${PLATFORM}-${SCREEN_SLUG}"
ASSET_DIR="$ROOT/dev/public/design/parts/${PLATFORM}/${SCREEN_SLUG}"
TS_DIR="$ROOT/dev/src/components/design/${PLATFORM}/${SCREEN_SLUG}"
MANIFEST="$ASSET_DIR/manifest.json"

[ -f "$MANIFEST" ] || { echo "::error:: not found: $MANIFEST (run gen-page-parts.sh first)" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "::error:: jq required" >&2; exit 3; }
if command -v magick >/dev/null 2>&1; then IM="magick"
elif command -v convert >/dev/null 2>&1; then IM="convert"
else echo "::error:: ImageMagick required (brew install imagemagick / apt install imagemagick)" >&2; exit 3
fi

IMG_COUNT=$(jq -r '.image_count // 0' "$MANIFEST")
case "$IMG_COUNT" in ''|*[!0-9]*) echo "::error:: manifest.image_count invalid: '$IMG_COUNT'" >&2; exit 1 ;; esac

mkdir -p "$ASSET_DIR" "$TS_DIR"

PARTS_TS="$TS_DIR/parts.ts"

# Zero-asset case: empty parts.ts, exit cleanly.
if [ "$IMG_COUNT" = "0" ]; then
  {
    printf '/** Auto-generated empty parts map for %s / %s (no non-HTML assets). */\n' "$PLATFORM" "$SCREEN_SLUG"
    printf 'export const parts = {} as const;\n'
    printf 'export type PartKey = keyof typeof parts;\n'
  } > "$PARTS_TS"
  echo "no assets to crop. wrote empty parts map: $PARTS_TS"
  exit 0
fi

# Verify every referenced grid image exists.
for ((i=0; i<IMG_COUNT; i++)); do
  GRID="${GRID_PREFIX}-${i}.png"
  [ -f "$GRID" ] || { echo "::error:: missing grid image: $GRID (gen-page-parts.sh should have produced it)" >&2; exit 1; }
done

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
  IMG=$(jq -r '.image // 0' <<<"$CELL")
  R=$(jq -r .row <<<"$CELL")
  C=$(jq -r .col <<<"$CELL")
  N=$(jq -r .name <<<"$CELL")
  case "$IMG$R$C" in ''|*[!0-9]*) echo "::warning:: bad cell image=$IMG row=$R col=$C, skip" >&2; continue ;; esac

  if [ "$IMG" -ge "$IMG_COUNT" ]; then
    echo "::warning:: cell '$N' references image $IMG but image_count=$IMG_COUNT, skip" >&2
    continue
  fi

  GRID="${GRID_PREFIX}-${IMG}.png"
  X=$(( CELL_SIZE * C ))
  Y=$(( CELL_SIZE * R ))
  OUT="$ASSET_DIR/${N}.png"

  $IM "$GRID" \
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
  echo "  cropped: $OUT  (image=$IMG @ ${X},${Y})"
done

printf '} as const;\n\nexport type PartKey = keyof typeof parts;\n' >> "$PARTS_TS"

echo
echo "assets:   $ASSET_DIR"
echo "parts.ts: $PARTS_TS"
echo "images:   $IMG_COUNT"
