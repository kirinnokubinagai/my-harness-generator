#!/usr/bin/env bash
# consult-phase.sh — Codex phase-specific second-opinion call. Auto-pastes
# the right input data (discoverySheet / feature list / data model / etc.)
# into the prompt template's placeholder, then calls codex-ask.sh.
#
# Caller (my-harness-init SKILL.md) must already have asked the user
# "Codex に二次チェックしてもらいますか?" and received yes. This script
# does the consult only — it never asks the user.
#
# Usage:
#   bash scripts/consult-phase.sh <phase-number> <root>

set -u

PHASE="${1:?phase number required (2|3|4|6|7|8)}"
ROOT="${2:?project root required}"

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_TMPL="$HARNESS_DIR/prompts/codex-consult-phase-${PHASE}.md"
INIT_STATE="$ROOT/.my-harness/init-state.json"
CONFIG="$ROOT/.my-harness/.config"

[ -f "$PROMPT_TMPL" ] || { echo "::error:: prompt template not found: $PROMPT_TMPL" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "::error:: jq required" >&2; exit 3; }

# Read template into a variable.
TEMPLATE=$(cat "$PROMPT_TMPL")

# Per-phase: pick role, fetch data, substitute placeholder.
EXTRA_CONTEXT=()

case "$PHASE" in
  2)
    ROLE="analyst"
    DATA=$(jq -c '.discoverySheet // {}' "$INIT_STATE" 2>/dev/null || echo '{}')
    BODY=${TEMPLATE//<PASTE_DISCOVERY_SHEET_JSON_HERE>/$DATA}
    ;;
  3)
    ROLE="architect"
    DISC=$(jq -c '.discoverySheet // {}' "$INIT_STATE" 2>/dev/null || echo '{}')
    # Pull a few key flags from .config to summarize the structural decisions.
    if [ -f "$CONFIG" ]; then
      STRUCT=$(awk -F= '
        $1=="ARCHITECTURE" || $1=="USE_WEB" || $1=="USE_IOS" || $1=="USE_ANDROID" || $1=="USE_DESKTOP" {
          gsub(/"/,"",$2); print $1": "$2
        }' "$CONFIG")
    else
      STRUCT="(config not found)"
    fi
    DATA=$(printf 'discoverySheet:\n%s\n\nstructural decisions:\n%s' "$DISC" "$STRUCT")
    BODY=${TEMPLATE//<PASTE_DISCOVERY_SHEET_AND_STRUCTURE_HERE>/$DATA}
    ;;
  4)
    ROLE="analyst"
    FEAT="$ROOT/dev/docs/spec/04-features.md"
    if [ -f "$FEAT" ]; then DATA=$(cat "$FEAT"); else DATA="(spec/04-features.md not found)"; fi
    BODY=${TEMPLATE//<PASTE_FEATURE_LIST_HERE>/$DATA}
    ;;
  6)
    ROLE="architect"
    CFG=$([ -f "$CONFIG" ] && cat "$CONFIG" || echo "(config not found)")
    MOCKS=$(jq -c '.visualMocks // []' "$INIT_STATE" 2>/dev/null || echo '[]')
    DATA=$(printf 'config:\n%s\n\nvisualMocks:\n%s' "$CFG" "$MOCKS")
    BODY=${TEMPLATE//<PASTE_CONFIG_AND_MOCKS_JSON_HERE>/$DATA}
    ;;
  7)
    ROLE="architect"
    DM="$ROOT/dev/docs/spec/07-data-model.md"
    if [ -f "$DM" ]; then DATA=$(cat "$DM"); else DATA="(spec/07-data-model.md not found)"; fi
    BODY=${TEMPLATE//<PASTE_DATA_MODEL_HERE>/$DATA}
    ;;
  8)
    ROLE="code-reviewer"
    BODY="$TEMPLATE"
    # Phase 8 uses --context for the spec + design instead of pasting.
    for f in "$ROOT/dev/docs/spec/"*.md; do [ -f "$f" ] && EXTRA_CONTEXT+=(--context "$f"); done
    for f in "$ROOT/dev/docs/design/"*.png; do [ -f "$f" ] && EXTRA_CONTEXT+=(--context "$f"); done
    ;;
  *)
    echo "::error:: unknown phase $PHASE (supported: 2 3 4 6 7 8)" >&2
    exit 1
    ;;
esac

# Substitute the universal placeholder.
BODY=${BODY//<root>/$ROOT}

OUT="$ROOT/.my-harness/codex-phase${PHASE}.md"
mkdir -p "$(dirname "$OUT")"

bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role "$ROLE" \
  --out "$OUT" \
  ${EXTRA_CONTEXT[@]+"${EXTRA_CONTEXT[@]}"} \
  "$BODY"
