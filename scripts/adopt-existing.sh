#!/usr/bin/env bash
# adopt-existing.sh — convert an existing git repo at <root> into the harness
# layout (.bare/ + main/stage/dev/ worktrees), preserving commit history.
#
# Steps:
#   1. Sanity: <root>/.git exists, <root>/.bare absent, working tree clean.
#   2. Back up <root>/.git to <root>/.my-harness-backup/<ts>/git/.
#   3. git clone --bare . <root>/.bare-tmp.
#   4. Move every top-level entry (except .git / .bare-tmp / .my-harness-backup /
#      .my-harness-stash-*) into <root>/.my-harness-stash-<ts>/.
#   5. rm -rf <root>/.git ; mv <root>/.bare-tmp <root>/.bare.
#   6. Ensure main / stage / dev branches exist in .bare (off current HEAD).
#   7. git worktree add main / stage / dev.
#   8. Move stashed entries into <root>/dev/.
#   9. If dev/ has uncommitted changes (it shouldn't — bare clone preserved HEAD),
#      git add -A && git commit on dev.
#  10. Fast-forward main and stage to dev where possible.
#
# Idempotent: refuses if .bare/ already exists. Backup of original .git is kept
# regardless so the user can roll back manually.
#
# Usage: bash adopt-existing.sh <project-root>

set -u

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  echo "::error:: adopt-existing.sh: missing <project-root>" >&2
  exit 64
fi
if ! ROOT="$(cd "$ROOT" 2>/dev/null && pwd)"; then
  echo "::error:: adopt-existing.sh: cannot cd to '$1'" >&2
  exit 65
fi

cd "$ROOT"

if [ ! -d ".git" ]; then
  echo "::error:: $ROOT/.git not found — not a git repository" >&2
  exit 1
fi
if [ -d ".bare" ]; then
  echo "::error:: $ROOT/.bare already exists — repo is already in harness layout" >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "::error:: working tree has uncommitted changes — commit or stash first" >&2
  exit 1
fi
if [ -z "$(git -C "$ROOT" rev-parse --verify HEAD 2>/dev/null)" ]; then
  echo "::error:: HEAD has no commits — make at least one commit before adopting" >&2
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$ROOT/.my-harness-backup/$TS"
STASH_DIR="$ROOT/.my-harness-stash-$TS"

echo "[adopt] backing up .git → $BACKUP_DIR/git" >&2
mkdir -p "$BACKUP_DIR"
cp -a .git "$BACKUP_DIR/git"

echo "[adopt] creating bare clone at .bare-tmp" >&2
if ! git clone --bare . .bare-tmp >/dev/null 2>"$BACKUP_DIR/clone.err"; then
  echo "::error:: git clone --bare failed (see $BACKUP_DIR/clone.err)" >&2
  rm -rf .bare-tmp
  exit 2
fi

echo "[adopt] stashing tracked entries → $STASH_DIR" >&2
mkdir -p "$STASH_DIR"
for entry in * .[!.]* ..?*; do
  [ -e "$entry" ] || continue
  case "$entry" in
    .git|.bare-tmp|.my-harness-backup|.my-harness-stash-*) ;;
    *) mv "$entry" "$STASH_DIR/" ;;
  esac
done

rm -rf .git
mv .bare-tmp .bare

# Ensure main / stage / dev branches.
HEAD_SHA=$(git --git-dir=.bare rev-parse HEAD 2>/dev/null)
if [ -z "$HEAD_SHA" ]; then
  echo "::error:: .bare HEAD is empty after clone — aborting" >&2
  exit 3
fi
if ! git --git-dir=.bare rev-parse --verify refs/heads/main >/dev/null 2>&1; then
  git --git-dir=.bare branch main "$HEAD_SHA"
fi
git --git-dir=.bare symbolic-ref HEAD refs/heads/main
for branch in stage dev; do
  if ! git --git-dir=.bare rev-parse --verify "refs/heads/$branch" >/dev/null 2>&1; then
    git --git-dir=.bare branch "$branch" main
  fi
done

echo "[adopt] adding worktrees: main / stage / dev" >&2
for wt in main stage dev; do
  if [ ! -d "$wt" ]; then
    git --git-dir=.bare worktree add --force "$wt" "$wt" >/dev/null 2>&1 || {
      echo "::error:: git worktree add $wt failed" >&2
      exit 4
    }
  fi
done

echo "[adopt] moving stashed entries into dev/" >&2
for entry in "$STASH_DIR"/* "$STASH_DIR"/.[!.]*; do
  [ -e "$entry" ] || continue
  base="$(basename "$entry")"
  case "$base" in
    .git) ;;
    *) mv "$entry" "dev/" ;;
  esac
done
rmdir "$STASH_DIR" 2>/dev/null || true

cd dev
if ! git diff --quiet || ! git diff --cached --quiet; then
  git add -A
  git commit -m "import: adopt existing repo into harness layout" >/dev/null
fi
cd "$ROOT"

# Fast-forward main / stage where dev is ahead (ignore failures).
for wt in main stage; do
  (cd "$wt" && git merge --ff-only dev >/dev/null 2>&1 || true)
done

cat >&2 <<EOF
[adopt] OK — layout is now {.bare, main, stage, dev}.
        Backup of original .git is at $BACKUP_DIR/git
        Next steps:
          1. Write or reuse $ROOT/.my-harness/.config (interview via /my-harness-adopt covers this).
          2. Run bootstrap.sh --config to install dev/.my-harness/, hooks, start-dev.sh.
          3. Restart Claude Code via $ROOT/start-dev.sh.
EOF
