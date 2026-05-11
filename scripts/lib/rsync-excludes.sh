#!/usr/bin/env bash
# rsync-excludes.sh — single source of truth for `dev/.my-harness/` rsync rules.
# Sourced by bootstrap.sh and /my-harness-adopt refresh path. Defines:
#
#   HARNESS_RSYNC_INCLUDES  — array of --include patterns
#   HARNESS_RSYNC_EXCLUDES  — array of --exclude patterns
#
# Add to either array, never inline new patterns at the call sites — that
# defeats the purpose of this file.

# shellcheck disable=SC2034
HARNESS_RSYNC_INCLUDES=(
  '/rules/'      '/rules/**'
  '/scripts/'    '/scripts/**'
  '/docs/'       '/docs/**'
)

# shellcheck disable=SC2034
HARNESS_RSYNC_EXCLUDES=(
  '*'                    # exclude everything not explicitly included
  '.git'
  '.git/**'
  'node_modules'
  'node_modules/**'
  '__pycache__'
  '*.pyc'
  '.DS_Store'
)

harness_rsync() {
  # Usage: harness_rsync <src> <dst>
  local src="$1" dst="$2"
  local args=()
  for p in "${HARNESS_RSYNC_INCLUDES[@]}"; do args+=(--include="$p"); done
  for p in "${HARNESS_RSYNC_EXCLUDES[@]}"; do args+=(--exclude="$p"); done
  rsync -a --delete "${args[@]}" "$src" "$dst"
}
