#!/usr/bin/env bash
# harness-task-status.sh — update a task's status (pending / in_progress / completed).
#
# When USE_GITHUB_ISSUES=no:
#   Update the `status:` line in the front matter of <root>/dev/docs/task/child/<id>.md
#   (or .../parent/<id>.md). Only the front matter `status:` line is touched.
#
# When USE_GITHUB_ISSUES=yes:
#   in_progress → `gh issue edit <id> --add-label in_progress --remove-label pending`
#   completed   → `gh issue close <id> --reason completed`
#   pending     → `gh issue edit <id> --add-label pending --remove-label in_progress`
#
# Why a script (not inline in analyst.md): keeps analyst.md short, fixes sed edge cases
# in one place (front matter `status:` line vs body lines that happen to start with the
# same word), and makes USE_GITHUB_ISSUES=yes/no symmetric for the caller.
#
# Usage:
#   bash harness-task-status.sh <root> <id> <new-status>
#     <root>       project root (the dir containing .my-harness/.config)
#     <id>         task id, e.g. 0001-07 (matches `id:` front matter)
#                  for parent tasks, pass parent id like 0001
#     <new-status> pending | in_progress | completed
#
# Exit codes:
#   0 on success, non-0 on hard failure (config missing / file missing / bad status / gh failure).

set -u

if [ $# -ne 3 ]; then
  echo "::error:: harness-task-status.sh requires 3 args: <root> <id> <new-status>" >&2
  exit 64
fi

ROOT="$1"
ID="$2"
NEW_STATUS="$3"
CFG="$ROOT/.my-harness/.config"

case "$NEW_STATUS" in
  pending|in_progress|completed) : ;;
  *)
    echo "::error:: invalid status '$NEW_STATUS' (allowed: pending / in_progress / completed)" >&2
    exit 65
    ;;
esac

if [ ! -f "$CFG" ]; then
  echo "::error:: $CFG not found (project not initialized)" >&2
  exit 1
fi

USE_GITHUB=$(grep -E "^USE_GITHUB_ISSUES=" "$CFG" | head -1 | cut -d= -f2 | tr -d '"')

if [ "$USE_GITHUB" = "yes" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "::error:: USE_GITHUB_ISSUES=yes but \`gh\` CLI not in PATH" >&2
    exit 2
  fi
  case "$NEW_STATUS" in
    in_progress)
      gh issue edit "$ID" --add-label in_progress --remove-label pending 2>&1 || exit $?
      ;;
    completed)
      gh issue close "$ID" --reason completed 2>&1 || exit $?
      ;;
    pending)
      gh issue edit "$ID" --add-label pending --remove-label in_progress 2>&1 || exit $?
      ;;
  esac
  echo "[harness-task-status] gh issue #$ID -> $NEW_STATUS" >&2
  exit 0
fi

# USE_GITHUB_ISSUES=no — find and edit the local task md.
TASK_FILE=""
for d in "$ROOT/dev/docs/task/child" "$ROOT/docs/task/child" "$ROOT/dev/docs/task/parent" "$ROOT/docs/task/parent"; do
  [ -d "$d" ] || continue
  for f in "$d"/*.md; do
    [ -f "$f" ] || continue
    FRONT_ID=$(awk '/^---$/{c++; next} c==1 && /^id:/{sub(/^id: */,""); print; exit} c==1 && /^parent:/{sub(/^parent: */,""); pid=$0} c>=2{exit} END{if(!ft && pid) print pid}' ft=1 "$f")
    # Cleaner: read just the id field; fall back to parent for parent files.
    FRONT_ID=$(awk -v want="$ID" '
      BEGIN { in_fm = 0; matched = 0 }
      /^---$/ { in_fm++; next }
      in_fm == 1 && /^id:[[:space:]]*/ {
        v = $0; sub(/^id:[[:space:]]*/, "", v)
        if (v == want) matched = 1
      }
      in_fm == 1 && /^parent:[[:space:]]*/ {
        v = $0; sub(/^parent:[[:space:]]*/, "", v)
        # Parent file has parent: <id> and no separate id: field — match if want equals parent.
        if (v == want && matched == 0) matched = 2
      }
      in_fm >= 2 { exit }
      END { print matched }
    ' "$f")
    if [ "$FRONT_ID" != "0" ] && [ -n "$FRONT_ID" ]; then
      TASK_FILE="$f"
      break 2
    fi
  done
done

if [ -z "$TASK_FILE" ]; then
  echo "::error:: harness-task-status.sh: no task md with id='$ID' found under $ROOT/(dev/)?docs/task/{child,parent}/" >&2
  exit 3
fi

# Update only the FIRST `status:` line inside the front matter (between the first two `---`).
TMP="$TASK_FILE.tmp.$$"
awk -v new="$NEW_STATUS" '
  BEGIN { in_fm = 0; updated = 0 }
  /^---$/ { in_fm++; print; next }
  in_fm == 1 && updated == 0 && /^status:[[:space:]]*/ {
    print "status: " new
    updated = 1
    next
  }
  { print }
' "$TASK_FILE" > "$TMP"

if ! grep -q "^status: $NEW_STATUS$" "$TMP"; then
  echo "::error:: harness-task-status.sh: failed to set status to '$NEW_STATUS' in $TASK_FILE" >&2
  rm -f "$TMP"
  exit 4
fi

mv "$TMP" "$TASK_FILE"
echo "[harness-task-status] $TASK_FILE -> status: $NEW_STATUS" >&2
