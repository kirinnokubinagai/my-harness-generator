#!/usr/bin/env bash
# crop-parts.sh — slice every parts-grid PNG into transparent-background
# per-part PNGs. Supports manifests that span MULTIPLE grid images:
# each cell has an `image` index pointing at the right
# parts-grid-<platform>-<screen-slug>-<image>.png to source from.
#
# Cell size is FIXED at 256×256 (override via env CELL_SIZE). Cropping is
# fully deterministic from manifest indices — no Vision required.
#
# Background removal uses CHROMA KEY on pure magenta `#FF00FF` (the color
# Codex paints the grid background per prompts/codex-parts-grid-edit.md).
# This means WHITE PIXELS INSIDE ASSETS ARE PRESERVED — clouds, paper,
# white snow, white speech bubbles, white logos all stay opaque white in
# the cropped PNG. Override the key color via env CHROMA_KEY (e.g.,
# CHROMA_KEY='#00FF00' for legacy green-screen) or the fuzz tolerance via
# CHROMA_FUZZ (default 10%).
#
# Outputs:
#   <root>/dev/docs/design/parts/<form-factor>/<screen-slug>/<name>.png     transparent PNG asset
#   <root>/dev/src/components/design/<form-factor>/<screen-slug>/parts.ts   TS import map
#
# Requires: ImageMagick (magick or convert) + jq.

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_SLUG="${3:?screen-slug required}"
CELL_SIZE="${CELL_SIZE:-256}"

# Chroma key color — priority: env (CHROMA_KEY or HARNESS_CHROMA_KEY) >
# saved file written by gen-page-parts.sh > default. Pinning the key from
# one source ensures gen-page-parts.sh (which told Codex what color to
# paint the background) and crop-parts.sh (which removes that color) agree.
SAVED_KEY_FILE="$ROOT/.my-harness/chroma-key.txt"
if [ -n "${CHROMA_KEY:-}" ]; then
  : # explicit env wins
elif [ -n "${HARNESS_CHROMA_KEY:-}" ]; then
  CHROMA_KEY="$HARNESS_CHROMA_KEY"
elif [ -f "$SAVED_KEY_FILE" ]; then
  CHROMA_KEY=$(head -n 1 "$SAVED_KEY_FILE")
else
  CHROMA_KEY="#FF00FF"
fi

# Magenta chroma key via Aral Balkan's formula (industry-standard for
# colored-background removal, adapted from green-screen to magenta):
#
#     alpha = g - min(r, b) + 1       (clamped to [0,1] by ImageMagick)
#
# This single per-pixel calculation:
#   - drives pure magenta (r=1, g=0, b=1) to alpha=0 (fully transparent)
#   - leaves every non-magenta pixel at alpha=1 (fully opaque)
#   - produces low alpha (~0–30%) on magenta-tinted edge pixels and high
#     alpha (~70–100%) on real asset edges, with a fade in between
#   - never touches the RGB channels, so asset-internal colors (white,
#     pink, purple — anything that is not pure magenta) are preserved.
#
# CHROMA_FLOOR controls the cut for residual magenta WITHOUT hardening
# real asset edges. The pipeline applies `-channel A -level <floor>x100%`:
#   - pixels with computed alpha ≤ floor become fully transparent
#     (this is where magenta-tinted edge pixels get killed)
#   - pixels with alpha ≥ 100% stay fully opaque
#   - the band in between is LINEARLY STRETCHED from 0% to 100%, so the
#     anti-aliased fade on real asset edges is preserved (just shifted
#     and steepened, not binarized).
#
# Default 30% works for typical gpt-image-2 output. Raise toward 50%
# for stricter magenta-residue removal at the cost of slightly tighter
# edges; lower toward 15% to preserve more anti-aliasing.
#
# Reference: https://ar.al/2021/11/23/how-to-apply-a-chroma-key-using-imagemagick/
CHROMA_FLOOR="${CHROMA_FLOOR:-30%}"

GRID_PREFIX="$ROOT/dev/docs/design/parts-grid-${PLATFORM}-${SCREEN_SLUG}"
ASSET_DIR="$ROOT/dev/docs/design/parts/${PLATFORM}/${SCREEN_SLUG}"
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

  # Single-pass magenta chroma key via Aral Balkan's formula. See the
  # CHROMA_THRESHOLD env block above for the full math.
  # Note: the formula below assumes magenta (#FF00FF); $CHROMA_KEY is no longer consulted.
  $IM "$GRID" \
    -crop "${CELL_SIZE}x${CELL_SIZE}+${X}+${Y}" +repage \
    -alpha set \
    -channel alpha -fx '1.0*g - min(r,b) + 1.0' +channel \
    -alpha on \
    -channel A -level "$CHROMA_FLOOR"x100% +channel \
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

# Auto-open every cropped part PNG so the user can inspect them.
# Suppress with HARNESS_SKIP_OPEN=1 (used by gen-page-cross-platform.sh).
# shellcheck disable=SC1091
HARNESS_DIR_CROP="$(cd "$(dirname "$0")/.." && pwd)"
. "$HARNESS_DIR_CROP/scripts/lib/open-file.sh"
# Collect cropped PNGs from manifest names (preserves Codex's natural ordering).
CROPPED=()
while IFS= read -r NAME; do
  [ -z "$NAME" ] && continue
  CROPPED+=("$ASSET_DIR/${NAME}.png")
done < <(jq -r '.cells[].name' "$MANIFEST")
[ "${#CROPPED[@]}" -gt 0 ] && open_file "${CROPPED[@]}"
