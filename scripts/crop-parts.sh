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

# Multi-layer chroma-key defense. The single -transparent pass that worked
# for clean computer-rendered backgrounds is not enough when Codex's
# `gpt-image-2` paints the magenta background with antialiased edges:
# pixels near the asset boundary blend toward pink (#FF80FF) and dusty
# rose, which a single fuzz pass on pure magenta does not always reach.
# We therefore stack four defenses, each tunable via env:
#
#   1. CHROMA_FUZZ      — primary fuzz around pure magenta. Default 40%
#                          (was 30%). Catches the bulk of antialiased rim.
#   2. CHROMA_HALO_COLOR / CHROMA_FUZZ_HALO — secondary -transparent pass
#                          on a mid-pink color to catch what the primary
#                          missed. Defaults: #FF80FF / 25%.
#   3. CHROMA_ERODE     — alpha-channel erosion after chroma keys. Default
#                          Octagon:2 (was Octagon:1). Two pixels of inward
#                          shrink kills the last residue at the boundary.
#   4. CHROMA_DESPILL   — pixel-level magenta cast suppression on whatever
#                          opaque pixels remain. When set to "yes" (default)
#                          a -fx filter detects (r>g && b>g) — the signature
#                          of leftover magenta tint — and raises green
#                          toward min(r,b) by 85%, neutralizing the cast
#                          without touching pixels that don't carry it.
#                          Set CHROMA_DESPILL=no to disable (faster, but
#                          may leave a faint magenta wash on textured edges).
#
# Override any of these for special assets that legitimately contain
# magenta-family colors (rare — magenta is reserved for background per
# prompts/codex-parts-grid-edit.md).
CHROMA_FUZZ="${CHROMA_FUZZ:-40%}"
CHROMA_HALO_COLOR="${CHROMA_HALO_COLOR:-#FF80FF}"
CHROMA_FUZZ_HALO="${CHROMA_FUZZ_HALO:-25%}"
CHROMA_ERODE="${CHROMA_ERODE:-Octagon:2}"
CHROMA_DESPILL="${CHROMA_DESPILL:-yes}"

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

  # Four-layer chroma key — see CHROMA_* env defaults block above for the
  # full rationale. The layers compose: stronger primary fuzz catches the
  # antialiased rim; a secondary mid-pink pass catches what survives;
  # alpha erode eats the last opaque-but-tinted pixels; despill -fx
  # neutralizes residual magenta cast on whatever opaque pixels remain.
  ERODE_OPS=()
  if [ -n "$CHROMA_ERODE" ]; then
    ERODE_OPS=(-channel A -morphology Erode "$CHROMA_ERODE" +channel)
  fi
  DESPILL_OPS=()
  if [ "$CHROMA_DESPILL" = "yes" ]; then
    # a==0 → skip transparent pixels (no need to alter them).
    # r>g && b>g → magenta cast signature (red+blue dominate green).
    # When that signature is present, lift green 85% of the way toward
    # min(r,b). This pulls magenta-tinted pixels toward neutral (white or
    # gray) without affecting true-color asset pixels where green is not
    # the minimum channel.
    DESPILL_OPS=(-channel RGBA -fx 'a==0 ? p : (r>g && b>g ? rgba(r, g + (min(r,b)-g)*0.85, b, a) : p)')
  fi
  $IM "$GRID" \
    -crop "${CELL_SIZE}x${CELL_SIZE}+${X}+${Y}" +repage \
    -alpha set \
    -fuzz "$CHROMA_FUZZ" \
    -transparent "$CHROMA_KEY" \
    -fuzz "$CHROMA_FUZZ_HALO" \
    -transparent "$CHROMA_HALO_COLOR" \
    "${ERODE_OPS[@]}" \
    "${DESPILL_OPS[@]}" \
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
