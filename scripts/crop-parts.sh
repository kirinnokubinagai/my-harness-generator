#!/usr/bin/env bash
# crop-parts.sh — slice the bottom-35 % parts grid of a page+parts image
# into individual component PNGs using ImageMagick.
#
# The image layout (produced by gen-page-parts.sh + Codex):
#   y = 0     .. 0.65 × H : full page mock (left untouched)
#   y = 0.65H .. H        : parts grid, 4 columns × N rows
#
# Caller passes the manifest describing what's in each cell (Claude reads the
# image via Vision first and produces this manifest as a JSON file). The
# script reads the manifest and crops each cell deterministically.
#
# Usage:
#   bash scripts/crop-parts.sh <root> <platform> <screen-slug> <manifest.json>
#
# Manifest format:
#   {
#     "rows": 3,
#     "cells": [
#       {"row": 0, "col": 0, "name": "primary-button"},
#       {"row": 0, "col": 1, "name": "primary-button-hover"},
#       ...
#     ]
#   }

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_SLUG="${3:?screen-slug required}"
MANIFEST="${4:?manifest.json required}"

IN_PNG="$ROOT/dev/docs/design/page-${PLATFORM}-${SCREEN_SLUG}.png"
[ -f "$IN_PNG" ]  || { echo "::error:: not found: $IN_PNG" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "::error:: not found: $MANIFEST" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "::error:: jq required" >&2; exit 3; }
command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 \
  || { echo "::error:: ImageMagick (magick or convert) required" >&2; exit 3; }

# Pick the right binary (ImageMagick 7 = magick; 6 = convert).
if command -v magick >/dev/null 2>&1; then IM="magick"; else IM="convert"; fi

# Image dimensions.
read -r IMG_W IMG_H < <($IM identify -format "%w %h" "$IN_PNG")
[ -n "${IMG_W:-}" ] && [ -n "${IMG_H:-}" ] || { echo "::error:: can't read $IN_PNG dimensions" >&2; exit 1; }

# Parts grid bounds: bottom 35 % of the image.
GRID_TOP=$(( IMG_H * 65 / 100 ))
GRID_H=$(( IMG_H - GRID_TOP ))

ROWS=$(jq -r .rows "$MANIFEST")
case "$ROWS" in ''|*[!0-9]*|0) echo "::error:: rows must be a positive integer (got: $ROWS)" >&2; exit 1 ;; esac

CELL_W=$(( IMG_W / 4 ))
CELL_H=$(( GRID_H / ROWS ))

OUT_DIR="$ROOT/dev/docs/design/parts/${PLATFORM}/${SCREEN_SLUG}"
mkdir -p "$OUT_DIR"
cp "$MANIFEST" "$OUT_DIR/manifest.json"

jq -c '.cells[]' "$MANIFEST" | while read -r CELL; do
  R=$(jq -r .row  <<<"$CELL")
  C=$(jq -r .col  <<<"$CELL")
  N=$(jq -r .name <<<"$CELL")
  case "$R$C" in ''|*[!0-9]*) echo "::warning:: bad cell row=$R col=$C, skip" >&2; continue ;; esac

  X=$(( CELL_W * C ))
  Y=$(( GRID_TOP + CELL_H * R ))
  OUT="$OUT_DIR/${N}.png"

  $IM "$IN_PNG" -crop "${CELL_W}x${CELL_H}+${X}+${Y}" +repage "$OUT"
  echo "  cropped: $OUT (${CELL_W}x${CELL_H} @ ${X},${Y})"
done

echo "parts directory: $OUT_DIR"
