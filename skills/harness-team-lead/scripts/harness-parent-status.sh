#!/usr/bin/env bash
# harness-parent-status.sh — close a parent task when all its children are completed.
#
# Called by analyst-N after marking its own child task completed (Step 5.5). If every
# child of the same parent now has status: completed, this script flips the parent's
# status to completed too.
#
# When USE_GITHUB_ISSUES=yes:
#   - Children = `gh issue list --label "parent-<id>"` (assumed labelling convention from
#     /my-harness-init).
#   - Parent close: gh issue close <parent-id> --reason completed.
# When USE_GITHUB_ISSUES=no:
#   - Children = <root>/(dev/)?docs/task/child/<parent-id>-*.md
#   - Parent file: <root>/(dev/)?docs/task/parent/<parent-id>-*.md
#   - Edit front-matter status: line via the same logic as harness-task-status.sh.
#
# Usage:
#   bash harness-parent-status.sh <root> <parent-id>
#
# Exit: 0 always (idempotent — parent already closed / not all children done are both
# silent no-ops; only hard failures (missing config / gh error) exit non-0).

set -u

if [ $# -ne 2 ]; then
  echo "::error:: harness-parent-status.sh requires 2 args: <root> <parent-id>" >&2
  exit 64
fi

ROOT="$1"
PARENT_ID="$2"
CFG="$ROOT/.my-harness/.config"

if [ ! -f "$CFG" ]; then
  echo "::error:: $CFG not found" >&2
  exit 1
fi

USE_GITHUB=$(grep -E "^USE_GITHUB_ISSUES=" "$CFG" | head -1 | cut -d= -f2 | tr -d '"')

if [ "$USE_GITHUB" = "yes" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "::error:: USE_GITHUB_ISSUES=yes but \`gh\` CLI not in PATH" >&2
    exit 2
  fi
  # All children with the parent-<id> label.
  OPEN=$(gh issue list --label "parent-$PARENT_ID" --state open --limit 200 --json number --jq '.[].number' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${OPEN:-0}" -gt 0 ]; then
    echo "[harness-parent-status] parent #$PARENT_ID: $OPEN child issue(s) still open — leaving parent open" >&2
    exit 0
  fi
  # All children closed → close parent.
  if gh issue view "$PARENT_ID" --json state --jq '.state' 2>/dev/null | grep -qx OPEN; then
    gh issue close "$PARENT_ID" --reason completed 2>&1 || exit $?
    echo "[harness-parent-status] closed parent issue #$PARENT_ID (all children completed)" >&2
  else
    echo "[harness-parent-status] parent #$PARENT_ID already closed — no-op" >&2
  fi
  exit 0
fi

# USE_GITHUB_ISSUES=no
CHILD_DIR=""
PARENT_DIR=""
for d in "$ROOT/dev/docs/task" "$ROOT/docs/task"; do
  if [ -d "$d/child" ] && [ -d "$d/parent" ]; then
    CHILD_DIR="$d/child"
    PARENT_DIR="$d/parent"
    break
  fi
done
if [ -z "$CHILD_DIR" ]; then
  echo "::error:: harness-parent-status.sh: docs/task/{child,parent} not found under $ROOT" >&2
  exit 3
fi

# Children of this parent: front matter `parent: <id>`.
PENDING_OR_INPROGRESS=0
for f in "$CHILD_DIR"/*.md; do
  [ -f "$f" ] || continue
  FM_PARENT=$(awk '/^---$/{c++; next} c==1 && /^parent:/{sub(/^parent:[[:space:]]*/,""); print; exit}' "$f")
  if [ "$FM_PARENT" = "$PARENT_ID" ]; then
    FM_STATUS=$(awk '/^---$/{c++; next} c==1 && /^status:/{sub(/^status:[[:space:]]*/,""); print; exit}' "$f")
    if [ "$FM_STATUS" != "completed" ]; then
      PENDING_OR_INPROGRESS=$((PENDING_OR_INPROGRESS + 1))
    fi
  fi
done

if [ "$PENDING_OR_INPROGRESS" -gt 0 ]; then
  echo "[harness-parent-status] parent $PARENT_ID: $PENDING_OR_INPROGRESS child(ren) still pending/in_progress — leaving parent open" >&2
  exit 0
fi

# Find the parent file (parent: <id> in front matter).
PARENT_FILE=""
for f in "$PARENT_DIR"/*.md; do
  [ -f "$f" ] || continue
  FM_PARENT=$(awk '/^---$/{c++; next} c==1 && /^parent:/{sub(/^parent:[[:space:]]*/,""); print; exit}' "$f")
  if [ "$FM_PARENT" = "$PARENT_ID" ]; then
    PARENT_FILE="$f"
    break
  fi
done

if [ -z "$PARENT_FILE" ]; then
  echo "[harness-parent-status] no parent md file with parent: $PARENT_ID — nothing to close" >&2
  exit 0
fi

# Already completed?
CURRENT_STATUS=$(awk '/^---$/{c++; next} c==1 && /^status:/{sub(/^status:[[:space:]]*/,""); print; exit}' "$PARENT_FILE")
if [ "$CURRENT_STATUS" = "completed" ]; then
  echo "[harness-parent-status] parent $PARENT_ID already completed — no-op" >&2
  exit 0
fi

# Flip parent's front-matter status to completed.
TMP="$PARENT_FILE.tmp.$$"
awk '
  BEGIN { in_fm = 0; updated = 0 }
  /^---$/ { in_fm++; print; next }
  in_fm == 1 && updated == 0 && /^status:[[:space:]]*/ {
    print "status: completed"
    updated = 1
    next
  }
  { print }
' "$PARENT_FILE" > "$TMP"

if ! grep -q "^status: completed$" "$TMP"; then
  echo "::error:: harness-parent-status.sh: failed to set parent status in $PARENT_FILE" >&2
  rm -f "$TMP"
  exit 4
fi

mv "$TMP" "$PARENT_FILE"
echo "[harness-parent-status] closed parent $PARENT_FILE (all children completed)" >&2
