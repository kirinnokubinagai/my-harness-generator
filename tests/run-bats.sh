#!/usr/bin/env bash
# run-bats.sh — convenience runner for the harness's bats tests.
#
# Looks for bats on PATH first (assumes you're inside `nix develop`).
# If not found, prints how to get it.
#
# Usage:
#   bash tests/run-bats.sh                  # run every .bats file under tests/bats/
#   bash tests/run-bats.sh ensure-codex     # only files matching pattern
#   bash tests/run-bats.sh --tap            # TAP output (for CI)

set -u

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BATS_DIR="$HARNESS_DIR/tests/bats"

if ! command -v bats >/dev/null 2>&1; then
  echo "::error:: bats not found on PATH" >&2
  echo "  enter the dev shell first:  nix develop" >&2
  echo "  or install ad-hoc:          nix shell nixpkgs#bats" >&2
  exit 127
fi

[ -d "$BATS_DIR" ] || { echo "::error:: $BATS_DIR not found" >&2; exit 1; }

ARGS=()
FILTER=""
for arg in "$@"; do
  case "$arg" in
    --tap|--no-tempdir-cleanup|--print-output-on-failure|--show-output-of-passing-tests|--verbose-run|--gather-test-outputs-in|--*)
      ARGS+=("$arg")
      ;;
    *)
      FILTER="$arg"
      ;;
  esac
done

if [ -n "$FILTER" ]; then
  FILES=("$BATS_DIR"/*"$FILTER"*.bats)
  if [ ! -f "${FILES[0]}" ]; then
    echo "::error:: no .bats files match pattern '*$FILTER*'" >&2
    exit 2
  fi
else
  FILES=("$BATS_DIR"/*.bats)
fi

echo "[run-bats] running ${#FILES[@]} file(s): $(printf '%s ' "${FILES[@]##*/}")"
if [ "${#ARGS[@]}" -gt 0 ]; then
  bats "${ARGS[@]}" "${FILES[@]}"
else
  bats "${FILES[@]}"
fi
