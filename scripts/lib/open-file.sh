#!/usr/bin/env bash
# open-file.sh — sourced helper. OS-aware "open file(s) in the system viewer".
#
# Usage (after `. "$HARNESS_DIR/scripts/lib/open-file.sh"`):
#   open_file path/to/a.png path/to/b.png ...
#
# Respects HARNESS_SKIP_OPEN=1 — when set, the function returns silently
# (used by cross-platform orchestrator to defer opening until all images
# across all platforms are ready, then opens them together).
#
# Fails silently if no opener is available — never blocks the caller.

# shellcheck shell=bash

open_file() {
  [ "${HARNESS_SKIP_OPEN:-0}" = "1" ] && return 0
  [ $# -eq 0 ] && return 0

  case "$(uname -s)" in
    Darwin)
      command -v open >/dev/null 2>&1 && open "$@" 2>/dev/null || true
      ;;
    Linux)
      if command -v xdg-open >/dev/null 2>&1; then
        for f in "$@"; do xdg-open "$f" >/dev/null 2>&1 & done
        wait 2>/dev/null || true
      fi
      ;;
    CYGWIN*|MINGW*|MSYS*)
      for f in "$@"; do (cmd.exe /c start "" "$f" 2>/dev/null &) || true; done
      ;;
    *) : ;;  # unsupported — silently noop
  esac
}
