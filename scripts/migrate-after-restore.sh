#!/usr/bin/env bash
# Summary: After restoring a production backup to stage, re-applies any additional migrations
#          that were in progress on stage. For D1, runs `wrangler d1 migrations apply`
#          targeting the stage environment.
# Usage: bash .harness/scripts/migrate-after-restore.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck disable=SC1091
[ -f .my-harness/.config ] && source .my-harness/.config || true

if [ "${DB_KIND:-none}" = "d1" ]; then
  echo "[migrate-after-restore] Re-applying additional migrations to D1 stage"
  # Apply migrations to the stage environment.
  # Right after restore, the tables are in the same state as production,
  # so this step is needed when schema changes were in progress on stage.
  nix develop --command pnpm exec wrangler d1 migrations apply DB --env staging --remote
else
  echo "[migrate-after-restore] No database in use. Skipping."
fi
