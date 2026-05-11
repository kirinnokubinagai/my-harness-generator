#!/usr/bin/env bash
# distribute-production.sh — copy production-grade templates into a freshly
# bootstrapped project. Sourced by bootstrap.sh after worktrees are live.
#
# Requires from caller:
#   HARNESS_DIR        — plugin root (so we can find templates/)
#   USE_BACKEND        — "yes"/"no"
#   BACKEND_KIND       — "hono"/"gin"/"rust"
#   copy_if_absent     — function defined in bootstrap.sh
#
# All copies are non-destructive: existing files in dev/ are kept.

# shellcheck shell=bash

distribute_production_templates() {
  copy_if_absent "$HARNESS_DIR/templates/docs/runbooks/*.md"                  "dev/docs/runbooks"
  copy_if_absent "$HARNESS_DIR/templates/github/workflows/codeql.yml"         "dev/.github/workflows"
  copy_if_absent "$HARNESS_DIR/templates/github/workflows/sbom.yml"           "dev/.github/workflows"
  copy_if_absent "$HARNESS_DIR/templates/github/workflows/license-check.yml"  "dev/.github/workflows"
  copy_if_absent "$HARNESS_DIR/templates/github/workflows/k6-smoke.yml"       "dev/.github/workflows"
  copy_if_absent "$HARNESS_DIR/templates/github/workflows/lighthouse.yml"     "dev/.github/workflows"
  copy_if_absent "$HARNESS_DIR/templates/github/renovate.json"                "dev"
  copy_if_absent "$HARNESS_DIR/templates/github/dependabot.yml"               "dev/.github"

  if [ "${USE_BACKEND:-no}" = "yes" ] && [ "${BACKEND_KIND:-hono}" = "hono" ]; then
    for sub in middleware routes lib; do
      copy_if_absent "$HARNESS_DIR/templates/backend/hono/$sub/*.ts" "dev/src/$sub"
    done
  fi
}
