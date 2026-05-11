#!/usr/bin/env bash
# Summary: Assembles a package.json containing only the dependencies needed based on bootstrap.env selections.
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"

# bootstrap.env is saved in $ROOT/.harness/ (copied to dev/.harness/ in a later step)
# shellcheck disable=SC1091
source "$ROOT/.my-harness/.config"

cd "$ROOT/dev"

# Common base
BASE='{
  "name": "'"$PROJECT_NAME"'",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "packageManager": "pnpm@9.15.0",
  "engines": { "node": ">=22" },
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "lint": "biome check .",
    "lint:fix": "biome check --write .",
    "format": "biome format --write .",
    "typecheck": "tsc --noEmit",
    "prepare": "husky"
  },
  "dependencies": {},
  "devDependencies": {
    "@biomejs/biome": "^2.4.13",
    "@types/node": "^22.13.0",
    "@commitlint/cli": "^19.7.0",
    "@commitlint/config-conventional": "^19.7.0",
    "husky": "^9.1.7",
    "tsx": "^4.20.0",
    "typescript": "^5.7.0",
    "vitest": "^4.1.5",
    "@vitest/coverage-v8": "^4.1.5"
  }
}'

# Add optional dependencies via jq
TMP=$(mktemp)
echo "$BASE" > "$TMP"

apply() { jq "$1" "$TMP" > "$TMP.next" && mv "$TMP.next" "$TMP"; }

if [ "$USE_WEB" = "yes" ]; then
  # Workers-target (rules/production.md). `wrangler dev` is local dev so KV / D1
  # / R2 bindings behave the same as prod.
  apply '.scripts += {
    "dev": "wrangler dev",
    "build": "tsc -p tsconfig.build.json",
    "deploy:dev":   "bunx alchemy deploy --stage dev",
    "deploy:stage": "bunx alchemy deploy --stage stage",
    "deploy:prod":  "bunx alchemy deploy --stage prod"
  } | .dependencies += {
    "hono": "^4.12.16",
    "@hono/zod-validator": "^0.7.0",
    "zod": "^3.25.0",
    "ulid": "^3.0.0",
    "pino": "^10.2.0",
    "@sentry/cloudflare": "^9.0.0"
  } | .devDependencies += {
    "alchemy": "2.0.0-beta.36",
    "effect": "^4.0.0",
    "@effect/platform-bun": "^0.0.0"
  }'
fi

if [ "$USE_PLAYWRIGHT" = "yes" ]; then
  apply '.scripts += { "test:e2e": "playwright test", "test:e2e:ui": "playwright test --ui" } |
         .devDependencies += { "@playwright/test": "^1.59.1" }'
fi

if [ "$DB_KIND" = "d1" ]; then
  apply '.scripts += {
    "db:generate": "drizzle-kit generate",
    "db:migrate:local": "wrangler d1 migrations apply DB --local",
    "db:migrate:remote": "wrangler d1 migrations apply DB --remote",
    "db:studio": "drizzle-kit studio"
  } | .dependencies += {
    "drizzle-orm": "^0.45.2"
  } | .devDependencies += {
    "drizzle-kit": "^0.45.2",
    "wrangler": "^3.99.0",
    "@cloudflare/workers-types": "^4.20260101.0"
  }'
fi

if [ "$USE_EMAIL" = "yes" ]; then
  apply '.dependencies += {
    "resend": "^6.12.2",
    "@react-email/components": "^0.4.0",
    "@react-email/render": "^1.4.0",
    "react": "^19.2.0",
    "react-dom": "^19.2.0"
  } | .devDependencies += {
    "@types/react": "^19.2.0",
    "@types/react-dom": "^19.2.0"
  }'
fi

if [ "$USE_MAESTRO" = "yes" ]; then
  apply '.scripts += { "test:e2e:mobile": "maestro test tests/e2e/mobile" }'
fi

mv "$TMP" package.json
echo "[generate-package-json] Done"
