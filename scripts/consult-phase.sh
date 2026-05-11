#!/usr/bin/env bash
# consult-phase.sh — invoke Codex for a phase-specific second-opinion review.
# Loads the prompt template from prompts/codex-consult-phase-<N>.{md,txt},
# substitutes <root> placeholders, and calls scripts/codex-ask.sh.
#
# Usage:
#   bash scripts/consult-phase.sh <phase-number> <root>
#
# The caller (my-harness-init SKILL.md) must already have asked the user
# "Codex に二次チェックしてもらいますか?" and received yes. This script
# does the call only — it never asks the user.

set -u

PHASE="${1:?phase number required (2|3|4|6|7|8)}"
ROOT="${2:?project root required}"

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="$HARNESS_DIR/prompts/codex-consult-phase-${PHASE}.md"

if [ ! -f "$PROMPT" ]; then
  echo "::error:: prompt template not found: $PROMPT" >&2
  exit 1
fi

case "$PHASE" in
  2) ROLE="analyst" ;;
  3|6|7) ROLE="architect" ;;
  4) ROLE="analyst" ;;
  8) ROLE="code-reviewer" ;;
  *) echo "::error:: unknown phase $PHASE" >&2; exit 1 ;;
esac

OUT="$ROOT/.my-harness/codex-phase${PHASE}.md"
mkdir -p "$(dirname "$OUT")"

# Substitute <root> in the prompt body so prompts can reference paths.
PROMPT_TEXT=$(sed "s|<root>|$ROOT|g" "$PROMPT")

bash "$HARNESS_DIR/scripts/codex-ask.sh" \
  --role "$ROLE" \
  --out "$OUT" \
  "$PROMPT_TEXT"
