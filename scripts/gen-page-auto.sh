#!/usr/bin/env bash
# gen-page-auto.sh — generate page mocks + parts grids for every form
# factor implied by the project's .config, on the SAME Codex session.
#
# Rules (read from <root>/.my-harness/.config):
#   NEED_PC     = USE_WEB == yes  OR  USE_DESKTOP == yes
#   NEED_MOBILE = USE_WEB == yes  OR  USE_IOS == yes  OR  USE_ANDROID == yes
#
# Order: PC first (when needed), then mobile. Mobile inherits PC's
# style_guide via prior-manifest discovery inside gen-page-parts.sh AND
# via Codex's session context (the PC mock image is visible to edit mode
# when the mobile turn runs).
#
# Auto-opens every produced PNG together at the end (so PC + mobile open
# side by side for direct comparison).
#
# Usage:
#   bash scripts/gen-page-auto.sh <root> <screen-name> <project-name>

set -u

ROOT="${1:?root required}"
SCREEN_NAME="${2:?screen name required}"
PROJECT_NAME="${3:?project name required}"

CONFIG="$ROOT/.my-harness/.config"
[ -f "$CONFIG" ] || { echo "::error:: $CONFIG missing — run /my-harness-init Phase 1 setup first" >&2; exit 1; }

get_flag() { grep -E "^$1=" "$CONFIG" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"' ; }

USE_WEB=$(get_flag USE_WEB)
USE_IOS=$(get_flag USE_IOS)
USE_ANDROID=$(get_flag USE_ANDROID)
USE_DESKTOP=$(get_flag USE_DESKTOP)

NEED_PC=no
NEED_MOBILE=no
{ [ "$USE_WEB" = "yes" ] || [ "$USE_DESKTOP" = "yes" ]; } && NEED_PC=yes
{ [ "$USE_WEB" = "yes" ] || [ "$USE_IOS" = "yes" ] || [ "$USE_ANDROID" = "yes" ]; } && NEED_MOBILE=yes

if [ "$NEED_PC" = "no" ] && [ "$NEED_MOBILE" = "no" ]; then
  echo "::error:: no form factor required — set at least one of USE_WEB / USE_IOS / USE_ANDROID / USE_DESKTOP to 'yes' in $CONFIG" >&2
  exit 1
fi

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCREEN_SLUG=$(printf '%s' "$SCREEN_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | tr ' /' '--' \
  | sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')
SCREEN_SLUG=${SCREEN_SLUG:-screen}

echo "=== gen-page-auto: screen='$SCREEN_NAME' (slug=$SCREEN_SLUG) ==="
echo "    NEED_PC=$NEED_PC  NEED_MOBILE=$NEED_MOBILE  (.config flags: WEB=$USE_WEB IOS=$USE_IOS ANDROID=$USE_ANDROID DESKTOP=$USE_DESKTOP)"

OPEN_LIST=()
FAILED=()

# Always run PC before mobile so mobile inherits PC's invariants. Within
# each child gen-page-parts.sh, defer per-form-factor auto-open via
# HARNESS_SKIP_OPEN=1 — we open everything together at the end here.
for FF in pc mobile; do
  case "$FF" in
    pc)     [ "$NEED_PC" = "yes" ]     || continue ;;
    mobile) [ "$NEED_MOBILE" = "yes" ] || continue ;;
  esac

  echo
  echo "============================================================"
  echo "=== Form factor: $FF / Screen: $SCREEN_NAME"
  echo "============================================================"
  if HARNESS_SKIP_OPEN=1 bash "$HARNESS_DIR/scripts/gen-page-parts.sh" "$ROOT" "$FF" "$SCREEN_NAME" "$PROJECT_NAME"; then
    OPEN_LIST+=("$ROOT/dev/docs/design/page-${FF}-${SCREEN_SLUG}.png")
    for g in "$ROOT/dev/docs/design/parts-grid-${FF}-${SCREEN_SLUG}-"*.png; do
      [ -f "$g" ] && OPEN_LIST+=("$g")
    done
  else
    FAILED+=("$FF")
    echo "::warning:: gen-page-parts.sh failed for form factor '$FF'" >&2
  fi
done

# shellcheck disable=SC1091
. "$HARNESS_DIR/scripts/lib/open-file.sh"
if [ "${#OPEN_LIST[@]}" -gt 0 ]; then
  echo
  echo "=== Opening ${#OPEN_LIST[@]} image(s) ==="
  open_file "${OPEN_LIST[@]}"
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "::error:: failed form factor(s): ${FAILED[*]}. Codex session preserved at $ROOT/.my-harness/codex-session-design-image.txt — re-run gen-page-parts.sh for the failed form factor to resume." >&2
  exit 2
fi
