#!/usr/bin/env bash
# gen-html-all.sh — second-stage Phase 5 batch: after every screen's PNGs
# are locked in (via gen-page-auto.sh), generate the Tailwind HTML for
# every (form-factor, screen) pair by invoking gen-page-html.sh.
#
# Why a separate stage instead of inlining into gen-page-auto.sh:
#   The user's preferred flow is "all PNGs first, all HTMLs second" so the
#   entire project's visual identity is approved across every screen
#   before any HTML gets written. That gives Codex's HTML session a fully
#   settled set of mocks + style_guide to draw from, and lets the user
#   spot palette/character drift across screens before committing it to
#   markup.
#
# Skips automatically when USE_CODEX != yes (HTML generation in that
# case is Claude's responsibility — see SKILL.md Phase 5).
#
# Discovers (form-factor, screen-slug) pairs by scanning
#   <root>/dev/docs/design/parts/*/*/manifest.json
# Order matters within form factors — PC HTML first per screen, then
# mobile — so HTML pairs open side-by-side in the same order as the PNGs.
#
# Usage:
#   bash scripts/gen-html-all.sh <root>

set -u

ROOT="${1:?root required}"

CONFIG="$ROOT/.my-harness/.config"
[ -f "$CONFIG" ] || { echo "::error:: $CONFIG missing — run /my-harness-init Phase 1 setup first" >&2; exit 1; }

get_flag() { grep -E "^$1=" "$CONFIG" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"' ; }

USE_CODEX=$(get_flag USE_CODEX)
PROJECT_NAME=$(get_flag PROJECT_NAME)

if [ "$USE_CODEX" != "yes" ]; then
  echo "[gen-html-all] USE_CODEX != yes — skipping Codex HTML generation. HTML is Claude's responsibility (see SKILL.md Phase 5 USE_CODEX=no path)." >&2
  exit 0
fi

[ -n "$PROJECT_NAME" ] || { echo "::error:: PROJECT_NAME missing from $CONFIG" >&2; exit 1; }

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Discover every (form-factor, screen-slug) pair via the manifest tree.
# Sort: PC before mobile, then by screen-slug alphabetically. We prefix
# each line with an integer priority so `sort` orders pc(0) before
# mobile(1) before anything-else(9), then strip the prefix.
PAIRS=()
while IFS= read -r line; do
  PAIRS+=("$line")
done < <(
  find "$ROOT/dev/docs/design/parts" -type f -name 'manifest.json' 2>/dev/null \
  | while IFS= read -r m; do
      rel="${m#"$ROOT/dev/docs/design/parts/"}"
      ff="${rel%%/*}"
      rest="${rel#*/}"
      slug="${rest%%/*}"
      if   [ "$ff" = "pc" ];     then order=0
      elif [ "$ff" = "mobile" ]; then order=1
      else                            order=9
      fi
      printf '%d %s %s\n' "$order" "$ff" "$slug"
    done \
  | LC_ALL=C sort -k1,1n -k3,3 \
  | cut -d' ' -f2-
)

if [ "${#PAIRS[@]}" -eq 0 ]; then
  echo "::error:: no manifests found under $ROOT/dev/docs/design/parts — run gen-page-auto.sh first" >&2
  exit 1
fi

echo "=== gen-html-all: ${#PAIRS[@]} pair(s) to convert to HTML ==="
for p in "${PAIRS[@]}"; do echo "  - $p"; done

OPEN_LIST=()
FAILED=()
for p in "${PAIRS[@]}"; do
  ff="${p%% *}"
  slug="${p#* }"
  echo
  echo "------------------------------------------------------------"
  echo "    [html] $ff / $slug"
  echo "------------------------------------------------------------"
  if HARNESS_SKIP_OPEN=1 bash "$HARNESS_DIR/scripts/gen-page-html.sh" "$ROOT" "$ff" "$slug" "$PROJECT_NAME"; then
    OPEN_LIST+=("$ROOT/dev/docs/design/page-${ff}-${slug}.html")
  else
    FAILED+=("${ff}/${slug}")
    echo "::warning:: gen-page-html.sh failed for $ff/$slug" >&2
  fi
done

# Open every produced HTML together so the user can review the batch.
# shellcheck disable=SC1091
. "$HARNESS_DIR/scripts/lib/open-file.sh"
if [ "${#OPEN_LIST[@]}" -gt 0 ]; then
  echo
  echo "=== Opening ${#OPEN_LIST[@]} HTML file(s) ==="
  open_file "${OPEN_LIST[@]}"
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "::error:: failed pair(s): ${FAILED[*]}. Session preserved at $ROOT/.my-harness/codex-session-design-html.txt — rerun gen-page-html.sh manually for each to retry." >&2
  exit 2
fi
