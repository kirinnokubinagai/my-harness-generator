#!/usr/bin/env bash
# gen-page-parts.sh — generate a high-quality page mock + parts grid image
# via Codex (gpt-image-2). One image contains BOTH the full page (top 65 %)
# and a 4-column grid of every distinct UI component used (bottom 35 %).
#
# Caller (my-harness-init Phase 5) must already have asked the user "Codex で
# このページのデザインを作りますか?" and received yes. This script does the
# generation only.
#
# Usage:
#   bash scripts/gen-page-parts.sh <root> <platform> <screen-name> <project-name>
#
#   <platform>     — web|ios|android|desktop
#   <screen-name>  — human-readable (e.g., "ログイン", "Dashboard")
#   <project-name> — for the prompt

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_NAME="${3:?screen name required}"
PROJECT_NAME="${4:?project name required}"

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_TMPL="$HARNESS_DIR/prompts/codex-page-and-parts.md"
[ -f "$PROMPT_TMPL" ] || { echo "::error:: $PROMPT_TMPL not found" >&2; exit 1; }

# slug from screen name: lowercase, ASCII-safe
SCREEN_SLUG=$(printf '%s' "$SCREEN_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | tr ' /' '--' \
  | sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')
SCREEN_SLUG=${SCREEN_SLUG:-screen}

mkdir -p "$ROOT/dev/docs/design"
OUT_PNG="$ROOT/dev/docs/design/page-${PLATFORM}-${SCREEN_SLUG}.png"

# Fill in placeholders in the prompt.
PROMPT=$(sed \
  -e "s|<PROJECT_NAME>|$PROJECT_NAME|g" \
  -e "s|<PLATFORM>|$PLATFORM|g" \
  -e "s|<SCREEN_NAME>|$SCREEN_NAME|g" \
  -e "s|<SCREEN_SLUG>|$SCREEN_SLUG|g" \
  -e "s|<root>|$ROOT|g" \
  "$PROMPT_TMPL")

bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --context "$ROOT/dev/docs/spec/"*.md \
  --out "$ROOT/.my-harness/codex-page-${PLATFORM}-${SCREEN_SLUG}.md" \
  "$PROMPT"

# Verify the PNG actually exists and is a PNG.
if [ ! -f "$OUT_PNG" ]; then
  echo "::error:: expected output not found: $OUT_PNG" >&2
  exit 2
fi
if ! file "$OUT_PNG" | grep -q "PNG image"; then
  echo "::error:: $OUT_PNG is not a PNG (got: $(file "$OUT_PNG"))" >&2
  exit 2
fi

echo "$OUT_PNG"
