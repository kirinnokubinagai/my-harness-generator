#!/usr/bin/env bash
# harness-worktree.sh — add / remove a lane worktree, idempotent.
#
# Naming: <root>/lanes/feat-<id>-<slug>/   (matches existing /my-harness-init layout)
# Branch: feat/<id>-<slug>                  (created from origin/dev)
#
# Idempotent:
#   add:    if the worktree path already exists AND points to the expected branch,
#           do nothing (success). Otherwise create.
#   remove: if the worktree doesn't exist, do nothing (success). Otherwise remove.
#
# Why a script: team-lead Step 3c needs worktree creation before assigning to analyst-N,
# and Step 3e needs cleanup after PR completes. Both are easy to get wrong (force flags,
# branch deletion order, leftover .git/worktrees entries) — centralize them.
#
# Usage:
#   bash harness-worktree.sh add <root> <id> <slug>
#   bash harness-worktree.sh remove <root> <id> <slug>
#
# Example:
#   bash harness-worktree.sh add /Users/x/todo-app 0001-07 flake-nix-direnv
#   # → worktree at /Users/x/todo-app/lanes/feat-0001-07-flake-nix-direnv/
#   #   branch feat/0001-07-flake-nix-direnv (off origin/dev)
#
# Exit codes: 0 success, non-0 on hard failure.

set -u

if [ $# -lt 4 ]; then
  cat >&2 <<EOF
::error:: harness-worktree.sh requires 4 args: <action> <root> <id> <slug>
  actions: add | remove
  example: bash harness-worktree.sh add /Users/x/todo-app 0001-07 flake-nix-direnv
EOF
  exit 64
fi

ACTION="$1"
ROOT="$2"
ID="$3"
SLUG="$4"

case "$ACTION" in
  add|remove) : ;;
  *)
    echo "::error:: invalid action '$ACTION' (allowed: add / remove)" >&2
    exit 65
    ;;
esac

# Resolve the git dir. Bare-clone layout has .bare/ at the project root; fall back to
# treating $ROOT itself as a git worktree.
if [ -d "$ROOT/.bare" ]; then
  GIT_DIR="$ROOT/.bare"
elif [ -d "$ROOT/.git" ]; then
  GIT_DIR="$ROOT/.git"
elif git -C "$ROOT" rev-parse --git-common-dir >/dev/null 2>&1; then
  GIT_DIR=$(git -C "$ROOT" rev-parse --git-common-dir)
else
  echo "::error:: harness-worktree.sh: no .bare/ or .git/ found at $ROOT" >&2
  exit 1
fi

WT_PATH="$ROOT/lanes/feat-$ID-$SLUG"
BRANCH="feat/$ID-$SLUG"

case "$ACTION" in
  add)
    # Ensure parent dir exists
    mkdir -p "$ROOT/lanes"

    # Idempotency: already exists?
    if [ -d "$WT_PATH" ] && git -C "$WT_PATH" rev-parse --git-dir >/dev/null 2>&1; then
      EXISTING_BRANCH=$(git -C "$WT_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)
      if [ "$EXISTING_BRANCH" = "$BRANCH" ]; then
        echo "[harness-worktree] skip — $WT_PATH already on $BRANCH" >&2
        exit 0
      fi
      echo "::error:: harness-worktree.sh: $WT_PATH exists but on branch '$EXISTING_BRANCH', not '$BRANCH'" >&2
      exit 2
    fi

    # Fetch origin/dev with an explicit refspec so refs/remotes/origin/dev is
    # always populated (some bare clones lack the default `+refs/heads/*:refs/remotes/origin/*`
    # fetch refspec, in which case `git fetch origin dev` only updates FETCH_HEAD).
    if ! git --git-dir="$GIT_DIR" fetch origin '+refs/heads/dev:refs/remotes/origin/dev' 2>&1; then
      echo "::error:: harness-worktree.sh: git fetch origin dev failed (does origin have a 'dev' branch?)" >&2
      exit 3
    fi

    # If branch already exists locally (left over from a previous run), reuse it.
    if git --git-dir="$GIT_DIR" rev-parse --verify "refs/heads/$BRANCH" >/dev/null 2>&1; then
      git --git-dir="$GIT_DIR" worktree add "$WT_PATH" "$BRANCH" 2>&1 || exit $?
    else
      git --git-dir="$GIT_DIR" worktree add -b "$BRANCH" "$WT_PATH" refs/remotes/origin/dev 2>&1 || exit $?
    fi
    echo "[harness-worktree] added $WT_PATH (branch $BRANCH off origin/dev)" >&2
    ;;

  remove)
    if [ ! -d "$WT_PATH" ]; then
      # Maybe the dir is gone but git still thinks it's a worktree — prune.
      git --git-dir="$GIT_DIR" worktree prune 2>&1 || true
      echo "[harness-worktree] skip — $WT_PATH does not exist" >&2
      exit 0
    fi

    # Remove worktree (force in case of dirty state — analyst should have committed first).
    git --git-dir="$GIT_DIR" worktree remove --force "$WT_PATH" 2>&1 || {
      echo "::error:: harness-worktree.sh: failed to remove worktree $WT_PATH" >&2
      exit 4
    }

    # Delete the local branch (push happened earlier; remote has the commits).
    if git --git-dir="$GIT_DIR" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
      git --git-dir="$GIT_DIR" branch -D "$BRANCH" 2>&1 || {
        echo "[harness-worktree] warning: could not delete local branch $BRANCH" >&2
      }
    fi

    echo "[harness-worktree] removed $WT_PATH and branch $BRANCH" >&2
    ;;
esac
