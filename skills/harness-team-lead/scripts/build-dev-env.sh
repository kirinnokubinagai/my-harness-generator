#!/usr/bin/env bash
# Evaluate the project's nix dev shell ONCE per /harness-team-lead session and
# dump it as a sourceable bash file. Engineers `source` this file instead of
# wrapping each command in `nix develop --command`, which eliminates the
# 4× nix-evaluator + shellHook fork-out across 4 lanes (the proven cause of
# the kernel-watchdog panic at ~1000 node helpers).
#
# Usage:
#   bash build-dev-env.sh [<project-root>]      # defaults to $PWD
#
# Output (stdout, single line): absolute path to the generated env file.
# Output file: <project-root>/.my-harness/.harness-devenv.sh
#
# After this runs, engineers do:
#   source $ROOT/.my-harness/.harness-devenv.sh
#   pnpm install                                 # no nix develop --command needed
#   pnpm exec vitest related --run <test>
#
# Why this is better than direnv:
#   - direnv requires `direnv allow` per worktree, manually, by the user.
#   - direnv caches per-worktree, so 4 lanes still each pay the first-allow cost.
#   - nix print-dev-env runs the evaluator exactly once per session, all 4 lanes
#     reuse the bash output. No per-lane evaluator fork.
#
# Why this is better than `nix develop --command pnpm install`:
#   - That re-evaluates the flake every call (nix evaluator + shellHook fork).
#   - 4 lanes × N commands per lane × evaluator = the fork bomb that crashed the kernel.
#   - Sourcing a pre-built bash file is just shell `export` lines: ~0 fork.

set -u

ROOT="${1:-$PWD}"

if [ ! -f "$ROOT/.my-harness/.config" ]; then
  echo "::error:: build-dev-env.sh: $ROOT/.my-harness/.config not found" >&2
  exit 1
fi

# Locate flake.nix. The harness convention is that flake.nix lives at the dev/
# worktree (per bootstrap.sh / templates/nix/flake.nix). Project root rarely
# has its own flake.nix; if it does, prefer it.
FLAKE_DIR=""
for c in "$ROOT" "$ROOT/dev"; do
  if [ -f "$c/flake.nix" ]; then
    FLAKE_DIR="$c"
    break
  fi
done

if [ -z "$FLAKE_DIR" ]; then
  echo "::error:: build-dev-env.sh: no flake.nix found at $ROOT or $ROOT/dev" >&2
  echo "         The harness expects a flake.nix at one of those locations." >&2
  exit 2
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "::error:: build-dev-env.sh: nix CLI not found in PATH" >&2
  exit 3
fi

OUT_DIR="$ROOT/.my-harness"
OUT="$OUT_DIR/.harness-devenv.sh"
TMP="$OUT.tmp.$$"
ERR="$OUT.err.$$"

mkdir -p "$OUT_DIR"

echo "[build-dev-env] evaluating $FLAKE_DIR/flake.nix (one-shot, all 4 lanes will source the result)..." >&2

if ! nix print-dev-env --impure "$FLAKE_DIR" > "$TMP" 2>"$ERR"; then
  echo "::error:: build-dev-env.sh: nix print-dev-env failed. stderr:" >&2
  cat "$ERR" >&2
  rm -f "$TMP" "$ERR"
  exit 4
fi

# Sanity: ensure output is non-empty bash and has at least PATH or shellHook.
if ! grep -q "^export\|^PATH=\|^declare -" "$TMP"; then
  echo "::error:: build-dev-env.sh: nix print-dev-env produced an unexpected output" >&2
  echo "         (no export / PATH= / declare lines). Check $FLAKE_DIR/flake.nix." >&2
  rm -f "$TMP" "$ERR"
  exit 5
fi

mv "$TMP" "$OUT"
rm -f "$ERR"

# Append PATH-restore so git / gh / system tools remain available alongside the
# nix-provided pnpm / node / bun / etc. nix print-dev-env replaces $PATH with
# nix-store-only paths and saves the original to $nix_saved_PATH; we re-append it
# at the end so engineers can `git commit && gh pr create` without resorting to
# absolute paths or installing more tools into the flake.
{
  echo ""
  echo "# harness: restore system PATH so git / gh / coreutils remain available"
  echo "# alongside the nix-provided pnpm / node / bun / etc. nix tools take"
  echo "# precedence (they appear first); system tools fill in the gaps."
  echo '[ -n "${nix_saved_PATH:-}" ] && export PATH="$PATH:$nix_saved_PATH"'
} >> "$OUT"

SIZE=$(wc -c < "$OUT" | tr -d ' ')
echo "[build-dev-env] OK — $OUT ($SIZE bytes)" >&2
echo "[build-dev-env] engineers should: source $OUT (then pnpm/vitest/biome/tsc directly)" >&2

# Stdout: absolute path (so callers can pipe / capture)
echo "$OUT"
