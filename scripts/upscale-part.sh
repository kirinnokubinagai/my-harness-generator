#!/usr/bin/env bash
# upscale-part.sh — regenerate a single part at a larger target size via Codex.
#
# When a part's display size exceeds the 256×256 source (e.g., a hero
# illustration that needs to render at 1600×800), this script asks Codex to
# regenerate just that asset at the target resolution. It resumes the same
# Codex session as the original page generation so context (spec + prior
# design choices) is preserved.
#
# Output: <root>/dev/docs/design/parts/<form-factor>/<screen-slug>/<part>-<W>x<H>.png
# Also adds a key to parts.ts: e.g., heroIllustration1600x800.
#
# Usage:
#   bash scripts/upscale-part.sh <root> <platform> <screen-slug> <part-name> <width> <height>
#
# part-name is the kebab-case name from manifest.json (e.g., 'hero-illustration').

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_SLUG="${3:?screen-slug required}"
PART="${4:?part name required}"
W="${5:?target width required}"
H="${6:?target height required}"

case "$W" in ''|*[!0-9]*|0) echo "::error:: width must be positive integer (got: $W)" >&2; exit 1 ;; esac
case "$H" in ''|*[!0-9]*|0) echo "::error:: height must be positive integer (got: $H)" >&2; exit 1 ;; esac

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_DIR="$ROOT/dev/docs/design/parts/${PLATFORM}/${SCREEN_SLUG}"
TS_DIR="$ROOT/dev/src/components/design/${PLATFORM}/${SCREEN_SLUG}"
MANIFEST="$ASSET_DIR/manifest.json"
SOURCE_PNG="$ASSET_DIR/${PART}.png"

[ -f "$MANIFEST" ]   || { echo "::error:: $MANIFEST not found (run gen-page-parts.sh first)" >&2; exit 1; }
[ -f "$SOURCE_PNG" ] || { echo "::error:: $SOURCE_PNG not found (run crop-parts.sh first, or the part name is wrong)" >&2; exit 1; }
[ -f "$TS_DIR/parts.ts" ] || { echo "::error:: $TS_DIR/parts.ts not found" >&2; exit 1; }

# Confirm the part exists in manifest
if ! jq -e --arg n "$PART" '.cells[] | select(.name == $n)' "$MANIFEST" >/dev/null; then
  echo "::error:: '$PART' not in manifest. Known parts:" >&2
  jq -r '.cells[].name' "$MANIFEST" | sed 's/^/  - /' >&2
  exit 1
fi

OUT="$ASSET_DIR/${PART}-${W}x${H}.png"
# Project-wide image-generation session — same thread that originally drew
# the 256×256 part. Resuming it means Codex still knows the palette / style
# / composition decisions it applied to the smaller version.
SESSION_FILE="$ROOT/.my-harness/codex-session-design-image.txt"
[ -f "$SESSION_FILE" ] || { echo "::error:: $SESSION_FILE missing — re-run gen-page-parts.sh first to recreate the Codex session" >&2; exit 1; }
SESSION_KEY=$(cat "$SESSION_FILE")

PROMPT=$(cat <<EOF
\$imagegen Regenerate the part you previously drew as '$PART' on the '$SCREEN_SLUG' screen for the '$PLATFORM' platform of this project, but at a larger resolution. (This session contains every screen and platform for the project — be explicit about which part is being upscaled.)

Use the exact same design choices (palette, style, composition) as the 256×256 version. Just render it at the larger size with the additional fidelity that the extra pixels allow.

Technical:
- One image_gen call.
- Output size: ${W}×${H} pixels.
- Format: PNG with transparent background (alpha channel).
- Save to: $OUT
EOF
)

RESPONSE_OUT="$ROOT/.my-harness/codex-upscale-${PLATFORM}-${SCREEN_SLUG}-${PART}-${W}x${H}.md"

bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --out "$RESPONSE_OUT" \
  "$PROMPT"

if [ ! -f "$OUT" ] || ! file "$OUT" 2>/dev/null | grep -q "PNG image"; then
  echo "::error:: upscale failed — $OUT was not produced. Codex session '$SESSION_KEY' preserved." >&2
  exit 2
fi

# Append the new size to parts.ts (idempotent).
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

PARTS_TS="$TS_DIR/parts.ts"
KEY="$(camel_case "$PART")${W}x${H}"
REL_PATH="/design/parts/${PLATFORM}/${SCREEN_SLUG}/${PART}-${W}x${H}.png"
NEW_ENTRY="  ${KEY}: '${REL_PATH}',"

if grep -q "^[[:space:]]*${KEY}:" "$PARTS_TS"; then
  # Replace existing line
  sed -i.bak "s|^[[:space:]]*${KEY}:.*|${NEW_ENTRY}|" "$PARTS_TS"
  rm -f "${PARTS_TS}.bak"
else
  # Insert before the closing '} as const;'
  awk -v line="$NEW_ENTRY" '
    /^} as const;/ && !done { print line; done = 1 }
    { print }
  ' "$PARTS_TS" > "$PARTS_TS.tmp" && mv "$PARTS_TS.tmp" "$PARTS_TS"
fi

echo "upscaled: $OUT (${W}×${H})"
echo "parts.ts updated with key '$KEY'"
