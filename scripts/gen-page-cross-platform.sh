#!/usr/bin/env bash
# gen-page-cross-platform.sh — generate the same screen's page+parts on
# multiple platforms (e.g., web AND ios), then open every resulting PNG
# at the same time so the user can compare designs side by side.
#
# Internally runs scripts/gen-page-parts.sh once per platform (sequentially
# — Codex does not parallelize well per-account). Each invocation has its
# own deterministic --session key (per platform + screen), so a later
# refinement on one platform doesn't bleed into the other.
#
# Each child gen-page-parts.sh + its crop-parts.sh (if invoked separately)
# normally auto-opens its outputs. This wrapper sets HARNESS_SKIP_OPEN=1
# during children so nothing pops up mid-run; at the end it opens
# everything together.
#
# Usage:
#   bash scripts/gen-page-cross-platform.sh \
#     <root> <screen-name> <project-name> <platform1> [<platform2> ...]
#
# Example:
#   bash scripts/gen-page-cross-platform.sh \
#     ~/project "Login" "MyApp" web ios
# → generates page-web-login.png + page-ios-login.png (+ their parts grids)
#   then opens all of them at once.

set -u

ROOT="${1:?root required}"
SCREEN_NAME="${2:?screen name required}"
PROJECT_NAME="${3:?project name required}"
shift 3

[ $# -eq 0 ] && { echo "::error:: at least one platform required (e.g., web ios android desktop)" >&2; exit 1; }

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$HARNESS_DIR/scripts/gen-page-parts.sh"

SCREEN_SLUG=$(printf '%s' "$SCREEN_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | tr ' /' '--' \
  | sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')
SCREEN_SLUG=${SCREEN_SLUG:-screen}

OPEN_LIST=()
FAILED_PLATFORMS=()

for PLAT in "$@"; do
  echo
  echo "=== generating $PLAT / $SCREEN_NAME ==="
  if HARNESS_SKIP_OPEN=1 bash "$GEN" "$ROOT" "$PLAT" "$SCREEN_NAME" "$PROJECT_NAME"; then
    OPEN_LIST+=("$ROOT/dev/docs/design/page-${PLAT}-${SCREEN_SLUG}.png")
    # Add any grid images that ended up being produced.
    for g in "$ROOT/dev/docs/design/parts-grid-${PLAT}-${SCREEN_SLUG}-"*.png; do
      [ -f "$g" ] && OPEN_LIST+=("$g")
    done
  else
    FAILED_PLATFORMS+=("$PLAT")
    echo "::warning:: gen-page-parts.sh failed for $PLAT — see logs above" >&2
  fi
done

# shellcheck disable=SC1091
. "$HARNESS_DIR/scripts/lib/open-file.sh"

if [ "${#OPEN_LIST[@]}" -gt 0 ]; then
  echo
  echo "=== opening ${#OPEN_LIST[@]} image(s) ==="
  open_file "${OPEN_LIST[@]}"
fi

if [ "${#FAILED_PLATFORMS[@]}" -gt 0 ]; then
  echo "::error:: $((${#FAILED_PLATFORMS[@]})) platform(s) failed: ${FAILED_PLATFORMS[*]}" >&2
  echo "::error:: the Codex session for this project is preserved at $ROOT/.my-harness/codex-session-design-image.txt — retry by re-running gen-page-parts.sh for the failed platform; the session will resume the prior context." >&2
  exit 2
fi
