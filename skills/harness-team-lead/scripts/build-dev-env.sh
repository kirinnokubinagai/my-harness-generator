#!/usr/bin/env bash
# Build a project- or worktree-scoped nix dev shell once and dump it as a
# sourceable bash file. Per-worktree caching with mtime invalidation: the env
# is rebuilt only when flake.nix or flake.lock is newer than the cached env.
# Engineers source the env instead of wrapping each command in
# `nix develop --command`, which eliminates the 4× nix-evaluator + shellHook
# fork-out across 4 lanes (the verified cause of the kernel-watchdog panic at
# ~1000 node helpers).
#
# Usage:
#   bash build-dev-env.sh [<worktree-or-project-root>]
#     defaults to $PWD
#
# Behavior:
#   - Find the nearest flake.nix walking up from the given dir (worktree first,
#     then project parents). Each lane worktree typically has its own flake.nix
#     (git worktree of the same branch — initially identical, can diverge as
#     engineer-N edits flake.nix for an in-flight issue).
#   - Cache file lives at <worktree>/.my-harness/.harness-devenv.sh — per-worktree,
#     so per-lane edits to flake.nix produce per-lane env files.
#   - mtime cache: if env file exists AND is newer than flake.nix AND flake.lock,
#     skip rebuild (instant return — script noop).
#   - On rebuild: nix print-dev-env --impure → atomic write → append PATH-restore
#     line so git / gh / coreutils stay resolvable alongside nix-provided tools.
#   - Stdout (single line): absolute path of the generated env file (so caller can
#     pipe / capture). Stderr: progress messages.
#
# Why per-worktree, not project-shared:
#   - lane-3 may be editing flake.nix as part of an issue (e.g., flake-nix-direnv).
#     Their env must reflect their flake.nix, not dev/'s.
#   - /nix/store is system-shared, so per-lane evaluation only re-runs the
#     evaluator (cheap) — the actual package builds are cache hits.

set -u

START="${1:-$PWD}"

# Resolve absolute
if ! START="$(cd "$START" 2>/dev/null && pwd)"; then
  echo "::error:: build-dev-env.sh: cannot cd to $1" >&2
  exit 1
fi

# Find nearest flake.nix walking up from START.
FLAKE_DIR=""
SEARCH="$START"
while [ "$SEARCH" != "/" ]; do
  if [ -f "$SEARCH/flake.nix" ]; then
    FLAKE_DIR="$SEARCH"
    break
  fi
  SEARCH="$(dirname "$SEARCH")"
done

if [ -z "$FLAKE_DIR" ]; then
  echo "::error:: build-dev-env.sh: no flake.nix found at or above $START" >&2
  exit 2
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "::error:: build-dev-env.sh: nix CLI not found in PATH" >&2
  exit 3
fi

# Cache lives next to the flake (worktree-scoped).
OUT_DIR="$FLAKE_DIR/.my-harness"
OUT="$OUT_DIR/.harness-devenv.sh"
mkdir -p "$OUT_DIR"

# Cache check: hash flake.nix + flake.lock content and compare against the
# marker line we wrote into the env file at last build. mtime-based caching
# would miss same-second edits on macOS bash (which compares whole seconds).
compute_hash() {
  if [ -f "$FLAKE_DIR/flake.lock" ]; then
    cat "$FLAKE_DIR/flake.nix" "$FLAKE_DIR/flake.lock" | shasum -a 256 | awk '{print $1}'
  else
    cat "$FLAKE_DIR/flake.nix" | shasum -a 256 | awk '{print $1}'
  fi
}

CURRENT_HASH=$(compute_hash)
HASH_MARKER="# harness-flake-sha256:$CURRENT_HASH"

if [ -f "$OUT" ] && head -1 "$OUT" 2>/dev/null | grep -qx "$HASH_MARKER"; then
  echo "[build-dev-env] cache hit — $OUT (flake content unchanged since last build)" >&2
  echo "$OUT"
  exit 0
fi

TMP="$OUT.tmp.$$"
ERR="$OUT.err.$$"

echo "[build-dev-env] evaluating $FLAKE_DIR/flake.nix..." >&2

# Build into TMP starting with the hash marker so the cache check above can
# detect content equality without ever touching mtimes.
{
  echo "$HASH_MARKER"
  nix print-dev-env --impure "$FLAKE_DIR" 2>"$ERR"
} > "$TMP" || {
  echo "::error:: build-dev-env.sh: nix print-dev-env failed. stderr:" >&2
  cat "$ERR" >&2
  rm -f "$TMP" "$ERR"
  exit 4
}

# Sanity: ensure body (after the marker line) is non-empty bash with PATH or shellHook.
if ! tail -n +2 "$TMP" | grep -q "^export\|^PATH=\|^declare -"; then
  echo "::error:: build-dev-env.sh: nix print-dev-env produced an unexpected output" >&2
  echo "         (no export / PATH= / declare lines). Check $FLAKE_DIR/flake.nix." >&2
  cat "$ERR" >&2 2>/dev/null
  rm -f "$TMP" "$ERR"
  exit 5
fi

# Append PATH-restore so git / gh / system tools remain available alongside the
# nix-provided pnpm / node / bun / etc. nix print-dev-env replaces $PATH with
# nix-store-only paths and saves the original to $nix_saved_PATH; we re-append
# it at the end so engineers can `git commit && gh pr create` without resorting
# to absolute paths or installing more tools into the flake.
{
  echo ""
  echo "# harness: restore system PATH so git / gh / coreutils remain available"
  echo "# alongside the nix-provided pnpm / node / bun / etc. nix tools take"
  echo "# precedence (they appear first); system tools fill in the gaps."
  echo '[ -n "${nix_saved_PATH:-}" ] && export PATH="$PATH:$nix_saved_PATH"'
} >> "$TMP"

mv "$TMP" "$OUT"
rm -f "$ERR"

SIZE=$(wc -c < "$OUT" | tr -d ' ')
echo "[build-dev-env] OK — $OUT ($SIZE bytes)" >&2

echo "$OUT"
