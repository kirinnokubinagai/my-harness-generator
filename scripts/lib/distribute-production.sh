#!/usr/bin/env bash
# distribute-production.sh — copy production-grade templates into a freshly
# bootstrapped project. Sourced by bootstrap.sh after worktrees are live.
#
# Requires from caller:
#   HARNESS_DIR        — plugin root
#   copy_if_absent     — function defined in bootstrap.sh
#
# 5.2.0 で簡素化:
#   - CI workflow と renovate / dependabot は setup-common.sh の
#     cp_glob_if_missing が `templates/github/` 全体を処理するため、
#     ここでの個別コピーは重複だった (5.0/5.1 で混入していた)。
#   - Hono middleware / lib は `templates/web/src/{interfaces,infrastructure}/`
#     に移管したので setup-platforms.sh の rsync templates/web/ で配布される。
#   - 残った真の責務は runbook (`templates/docs/runbooks/*.md`) のみ。

# shellcheck shell=bash

distribute_production_templates() {
  copy_if_absent "$HARNESS_DIR/templates/docs/runbooks/*.md" "dev/docs/runbooks"
}
