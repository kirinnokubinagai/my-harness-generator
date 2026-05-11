#!/usr/bin/env bash
# gen-page-parts.sh — generate a high-quality page mock + parts grid image
# via Codex (gpt-image-2). One image contains BOTH the full page (top 65 %)
# and a 4-column grid of every distinct UI component used (bottom 35 %).
#
# Reliability: Codex sometimes returns a chat reply WITHOUT actually calling
# image_gen, so the expected PNG is missing. This script defends against that:
#
#   1. It pins a deterministic --session key per (root, platform, screen).
#      The same Codex thread is reused across the initial call and every
#      retry, so context (spec, prior reasoning) is preserved.
#   2. After every call, it checks whether the PNG actually landed at the
#      expected path AND is a valid PNG. If not, it follows up in the same
#      session with a short, explicit nudge ("you did not save the file —
#      call image_gen now"). Up to MAX_RETRY follow-ups.
#   3. Final exit code = 0 only if the PNG exists and `file` recognizes it.
#
# Caller (my-harness-init Phase 5) must already have asked the user
# "Codex でこのページのデザインを作りますか?" and received yes. This script
# does the generation only.
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

# Deterministic session key — same across initial call + retries + refinement.
# Refinement (handled by a separate script / inline command) MUST reuse this
# key so context is not lost.
SESSION_KEY="design-page-${PLATFORM}-${SCREEN_SLUG}"
echo "$SESSION_KEY" > "$ROOT/.my-harness/codex-session-design-${PLATFORM}-${SCREEN_SLUG}.txt"

# Fill in placeholders in the prompt body.
PROMPT=$(sed \
  -e "s|<PROJECT_NAME>|$PROJECT_NAME|g" \
  -e "s|<PLATFORM>|$PLATFORM|g" \
  -e "s|<SCREEN_NAME>|$SCREEN_NAME|g" \
  -e "s|<SCREEN_SLUG>|$SCREEN_SLUG|g" \
  -e "s|<root>|$ROOT|g" \
  "$PROMPT_TMPL")

# --- Verify helper -----------------------------------------------------------
png_ready() {
  [ -f "$OUT_PNG" ] && file "$OUT_PNG" 2>/dev/null | grep -q "PNG image"
}

# --- Initial call ------------------------------------------------------------
INITIAL_OUT="$ROOT/.my-harness/codex-page-${PLATFORM}-${SCREEN_SLUG}.md"

bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --context "$ROOT/dev/docs/spec/"*.md \
  --out "$INITIAL_OUT" \
  "$PROMPT"

# --- Retry loop --------------------------------------------------------------
MAX_RETRY=${HARNESS_GEN_RETRY:-3}
RETRY=0

while ! png_ready; do
  RETRY=$(( RETRY + 1 ))
  if [ "$RETRY" -gt "$MAX_RETRY" ]; then
    echo "::error:: $OUT_PNG was not generated after $MAX_RETRY retries." >&2
    echo "::error:: Codex session preserved at $SESSION_KEY; the user can resume manually." >&2
    exit 2
  fi

  echo "::warning:: PNG missing after attempt $RETRY/$MAX_RETRY. Asking Codex to retry in the same session." >&2

  # Determine the right nudge based on what happened.
  if [ -f "$OUT_PNG" ]; then
    NUDGE="The file at $OUT_PNG exists but is not a valid PNG. Regenerate it as a PNG using the image_gen tool only (not HTML / SVG / canvas / code). Overwrite the same path."
  else
    NUDGE="You replied with text but did not save the image. Call image_gen now and save the PNG to $OUT_PNG. Use the exact layout from the previous message (page mock top 65 %, parts grid bottom 35 %, 4-column layout, white background under the grid). One image_gen call total."
  fi

  bash "$HARNESS_DIR/scripts/codex-ask.sh" \
    --role designer \
    --session "$SESSION_KEY" \
    --out "$ROOT/.my-harness/codex-page-${PLATFORM}-${SCREEN_SLUG}-r${RETRY}.md" \
    "$NUDGE"
done

echo "$OUT_PNG"
echo "session: $SESSION_KEY  (resume with: bash scripts/codex-ask.sh --session $SESSION_KEY ...)"
