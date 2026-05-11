# Changelog

All notable changes documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [7.0.1] — 2026-05-11

UX/copy 修正パッチ。インタビューの選択肢ラベルに付いていた **`(Recommended)`
/ `（推奨）`** ラベル全削除 + `MVP` 文言の全削除。harness は本来「ユーザーの判
断空間」であるべきで、根拠のない誘導をしてはいけない。

### Fixed — interview の誘導語を全廃 (`skills/my-harness-init/SKILL.md`)

- Q2b Engineer runner: `Codex (Recommended)` → `Codex`
- Q2c E2E reviewer: `Claude (Recommended)` → `Claude` (説明文も trade-off 形式に書き換え)
- Q2d Reviewer runner: `Codex (Recommended)` → `Codex`
- Q3 Global CLAUDE.md: `Inherit (Recommended)` → `Inherit`
- Q4 Task management: `Local markdown (Recommended)` → `Local markdown` (説明文を trade-off に)
- 各 Map 行から `(Recommended)` を削除、`No default applied.` を明示

### Changed — Recommendation policy を strict 化

`SKILL.md` 末尾の policy を「根拠があれば Recommended OK」から **「いかなる選択肢にも `(Recommended)` / `(推奨)` / `Default` / `デフォルト` を付与してはいけない」** に強化。根拠がある場合は質問の前に独立した文として提示し、選択肢ラベルには載せない。

### Added — MVP wording forbidden 規約

`SKILL.md` policy セクションに「MVP という語は user-facing で禁止」を追記。代替: `first version` / `initial release` / `before launch`。

### Fixed — MVP 文言削除

- `rules/production.md` 冒頭の "what an MVP must add" → "what every generated project must have before its first launch"
- `docs/PRODUCTION.md`: "not just MVPs" → "with full controls"
- `README.md`: "no longer scaffolds an MVP" → "scaffolds projects with production controls wired in"
- `README.ja.md`: "MVP スキャフォールドではなく" → "そのまま本番に出せる" (重複削除)
- `docs/MULTI_TENANT.md`: "POC / MVP 段階" → "個人プロジェクト / 検証段階"
- `CHANGELOG.md` 5.0.0 / 7.0.0 エントリの MVP 言及を中立表現に置換

### Fixed — `USE_CODEX_E2E_REVIEWER` の非対称な default

`bootstrap.sh` で USE_CODEX_E2E_REVIEWER だけ default `"n"` (Claude) だったのを `"y"` に揃えた。他の `USE_CODEX_*` (analyst / engineer / reviewer) はすべて default `"y"` (Codex) だったので、根拠不明な非対称が解消。質問文の "test execution stays local" という誤解を生む補足も削除し "Playwright/Maestro always run under Claude" に改めた (実際の挙動は何も変わらない — Codex に渡るのは synthesis のみで execution は常に Claude)。

## [7.0.0] — 2026-05-11

**研究色の濃いアイデア (16-24) を 1 段ずつ最小実装に落とした「ops surface」リリース。**
スキャフォルドそのものは 6.0.0 で完成しているので、7.0.0 は **運用フェーズ** で
効くツール群を一気に揃える。

### Added — Pipeline 性能ベンチ (item 16)

- `scripts/bench.sh` — 固定 `.config` で bootstrap を走らせ、所要 ms を
  `bench-results.jsonl` に追記。プラグイン更新ごとに走らせれば performance
  regression を早期検出できる。出力に git rev を含めるので diff が読める。

### Added — Spec → Playwright E2E 自動生成 (item 17)

- 新 skill: `harness-gen-e2e` (`skills/harness-gen-e2e/SKILL.md`)
- `scripts/gen-e2e.sh` — `dev/docs/spec/features.md` の `## Feature: <name>` を
  awk で分割し、各機能を `prompts/spec-to-e2e.md` テンプレートに埋めて
  `codex-ask.sh --role harness-engineer` に渡す
- `prompts/spec-to-e2e.md` — 「happy 1 + sad 2、`data-testid` 優先、API モック禁止、
  ユーザー観点 assertion」の生成ルールをプロンプトに固定
- 既存テストは skip、`--dry-run` でプロンプトのみ確認可

### Added — Time-travel debugging (item 18)

- `scripts/replay-agent.sh` — `.my-harness/logs/agents.log` から `--lane <N>` /
  `--name <teammate>` / `--since <ISO>` / `--until <ISO>` で絞り込み、過去の
  レーン動作を時系列で再生する。postmortem や教育素材として使える。

### Added — Living architecture diagram (item 19)

- `scripts/architecture-diagram.sh` — `dev/src/` の相対 import を辿り、
  Clean Architecture の層別 (interfaces / application / domain / infrastructure) に
  クラスタリングした Mermaid 図を `dev/docs/architecture.mmd` に出力。
  layer ルール (`domain ← application ← others`) 違反を `architecture-meta.json`
  にリストアップし、違反があれば exit 2。
- `templates/github/workflows/architecture-diagram.yml` — `src/**` への PR で
  自動再生成 + 違反検出時に PR fail。違反なければ commit が自動 push される。

### Added — AI-suggested rollback (item 20)

- `templates/github/workflows/auto-revert.yml` — `pr-to-stage.yml` が
  workflow_run failure を返した場合、自動で:
  1. 直近の main → stage マージコミットを特定
  2. `revert/auto-<run-id>` ブランチを切って `git revert -m 1`
  3. `approved-for-stage` + `auto-revert` ラベル付きで PR を作成 (24h soak スキップ)
  4. on-call 向けの postmortem 案内を body に埋める

### Added — Codex コスト透明性 (item 22)

- `scripts/cost.sh` — `.my-harness/logs/codex-cost.jsonl` を読み、role 別 /
  model 別 / 期間別の集計を出力。`--json` で機械可読。デフォルト単価:
  gpt-5 ($5/1M in, $15/1M out)、o4-pro ($10/$30)、codex-mini ($1/$4)。
  ※ `codex-ask.sh` / `codex-exec.sh` 側で token 数を書き出す改修は別途必要
  (本リリースは集計層のみ — instrumentation は 7.1.0 で予定)

### Added — Spec → Issue → Lane の閉ループ (item 24)

- `scripts/spec-to-issues.sh` — `features.md` の各 `## Feature: <name>` を 1 issue
  にし、YAML フロントマターの `owned_files` / `lane_hint` を抽出して
  `gh issue create --label lane-hint:<N>` で登録。既存タイトル一致は skip
  (冪等)。`--dry-run` でプレビュー可。
- 仕様: `harness-team-lead` 側で `lane-hint:` ラベルと issue body の
  `<!-- owned_files: [...] -->` コメントを読み取り、レーン割当の入力として
  使う (lead SKILL.md の修正は 7.1.0 予定)

### Added — Cloudflare MCP server (item 23)

- `templates/mcp/cloudflare-server.ts` — `@modelcontextprotocol/sdk` ベースの
  stdio MCP server。Claude Code / Cursor / Aider 等から:
  - `list_workers` — アカウント内 Worker 一覧
  - `list_deployments` — 指定 Worker のデプロイ履歴
  - `rollback_deployment` — 指定 deployment ID にロールバック
  - `d1_query` — D1 に **SELECT のみ** 実行 (DML は server 側で拒否)
  を呼び出せる。デプロイ後の運用を AI から直接実行できる。

### Added — Multi-tenant migration guide (item 21)

- `docs/MULTI_TENANT.md` — `tenant_id` カラム追加、`tenants` テーブル設計、
  JWT に `tid` claim を埋める、tenant middleware、repository 全関数の第 2
  引数を tenantId に強制、rate-limit を per-tenant に切替、UNIQUE 制約の
  複合化、削除ポリシー (onDelete: restrict + 30 日論理削除 + GDPR 連携)、
  CI チェック追加までの完全手順。
- 戦略 3 種 (共有 DB / Schema 分離 / 完全分離 D1) の比較表付き。harness の
  default は意図的に single-tenant のまま — multi-tenant は **早ければ早い
  ほど安い** ので「production 前に検討せよ」と明示。

### 既知の積み残し (7.1.0 以降)

- Codex token instrumentation (`codex-ask.sh` / `codex-exec.sh` を改修して
  `codex-cost.jsonl` を書き出す)
- `harness-team-lead` SKILL.md に `lane-hint:` ラベル読み取りを配線
- multi-tenant ESLint カスタムルール
- spec-to-e2e の fixture (`tests/e2e/fixtures/auth.ts`) 自動生成

## [6.0.0] — 2026-05-11

**The "you can actually ship to production" release.** Bundles 5.2.1
(bug fixes), 5.3.0 (tests + DX), 5.4.0 (OpenAPI), and a thin but real auth
scaffold. The harness now goes from `/my-harness-init` to "an API with
working login, audit logging, rate limiting, idempotency, and
auto-generated OpenAPI docs" in one bootstrap.

### Added — auth scaffold (real, not stubbed)

- `dev/src/interfaces/http/routes/auth.ts` — `/auth/login`, `/auth/password-reset/request`, `/auth/password-reset/confirm` with full Zod schemas, rate-limit (5/15min login, 3/h password-reset), audit-log on every outcome, and OpenAPI definitions.
- `dev/src/application/auth/login.ts` — bcrypt-ts password verify + jose HS256 JWT issuance (15min TTL).
- `dev/src/application/auth/password-reset.ts` — 2-phase flow: SHA-256 hex token storage (never plaintext), 30-min expiry, `consumed_at` for replay prevention, enumeration-attack-resistant request endpoint.
- `dev/src/infrastructure/persistence/user-repository.ts` — Drizzle D1 adapter (`findUserByEmail`, reset-token CRUD, password update via D1 `batch` for atomicity).

### Added — OpenAPI + Scalar UI

- `@hono/zod-openapi` replaces `Hono` in `app.ts`. Every route declared with `createRoute({...})` produces OpenAPI 3.1 automatically.
- `GET /openapi.json` — machine-readable spec.
- `GET /docs` — Scalar API reference UI.
- Generated clients (TS / Python / Go / Rust) can be produced with `pnpm dlx openapi-typescript /openapi.json`.

### Added — Production Readiness Score

- `scripts/score.sh` — evaluates 18 production-readiness checks (runbooks, wrangler config, audit_log, Renovate, CodeQL, SBOM, license, k6, Lighthouse, SOPS, middleware suite, auth route, OpenAPI, tests) and prints a 0-100 score. `--json` for machine output.
- Exit codes: `0` (≥80), `1` (60-79), `2` (<60) — wire into CI as a release gate.

### Added — Tests (TDD compliance)

`rules/production.md` requires TDD strict but 5.0–5.2 shipped untested middleware. Now:

- `templates/web/src/interfaces/http/middleware/rate-limit.test.ts` — window boundary, limit enforcement, 429 response shape, Retry-After header.
- `templates/web/src/interfaces/http/middleware/idempotency.test.ts` — GET passthrough, replay caching, short-key 400, key-less passthrough.
- `templates/web/src/infrastructure/audit/audit-log.test.ts` — adapter contract verification, metadata JSON encoding, sql tag invocation.
- `templates/web/src/infrastructure/feature-flags/feature-flag.test.ts` — boolean / 0% / 100% / stable hash / WeakMap memoize.

### Added — 4.x → 5.x/6.x upgrade automation

- `scripts/upgrade-4-to-5.sh` — idempotent. Detects 4.x patterns (Node `@hono/node-server`, old `app.ts` signature, `wrangler.toml` only, missing `audit_log`), warns about manual steps, automatically removes the bad deps + drops missing runbooks. Run once after `/my-harness-adopt` against an adopted 4.x project.

### Added — Operational guidance baked in

- `templates/dotmyharness/learnings.md` → `dev/.my-harness/learnings.md` at bootstrap. All lane agents read this at ASSIGNMENT-time; new findings accumulate via PR review (blameless, no per-issue/lane names).
- `templates/dotmyharness/secrets-README.md` → `dev/secrets/README.md`. Concrete age-keygen + sops encrypt commands; CI integration via `AGE_SECRET_KEY_STAGE`.

### Changed — `doctor.sh` wired into the team-lead preflight

`skills/harness-team-lead/SKILL.md` Precondition now invokes
`bash $CLAUDE_PLUGIN_ROOT/scripts/doctor.sh` after `preflight.sh`. WARN
is advisory; FAIL stops the lead before the first lane spawn.

### Changed — package.json deps (USE_WEB=yes)

Added: `@hono/zod-openapi`, `@scalar/hono-api-reference`, `bcrypt-ts`, `jose`.

### Fixed — 5.2.0 carry-over bugs

- `wrangler.jsonc` / `alchemy.run.ts` / `lighthouserc.json` now have **`PROJECT_NAME`** substituted at bootstrap (was hard-coded `harness-app` / `harness`).
- `strictCors` no longer throws at module load when `ALLOWED_ORIGINS` is missing — defaults to `http://localhost:{3000,8787}` in non-prod (`ENVIRONMENT !== 'prod'`). Production still requires explicit allowlist.
- `pnpm dev` defaults to `wrangler dev --local --persist-to=.wrangler/state` so first-run works without real Cloudflare resource IDs. `pnpm dev:remote` opts in to the cloud bindings.
- `tsx watch` removed from `dev` script; `tsx` no longer relevant for Workers target.

### Removed

- `build: tsc -p tsconfig.build.json` script — Workers bundles internally via wrangler.

## [5.2.0] — 2026-05-11

Integration pass. 5.0/5.1 added production middleware / docs / CI workflows
but never connected them — the templates referenced KV bindings that didn't
exist in `wrangler.jsonc`, the worker entrypoint was Node-flavoured while
the deploy path was Workers, and `templates/backend/hono/` duplicated
`templates/web/src/`. This release wires it all together.

### BREAKING — Workers becomes the only production runtime

The harness now ships **Cloudflare Workers + D1** as the documented production
target. `@hono/node-server` is removed from generated `package.json`. Local
development uses `wrangler dev` (so KV / D1 / R2 bindings behave identically
to prod). Existing 4.x/5.x projects keep working but new `dev/src/main.ts`
is a `export default { fetch }` Workers handler.

### Added — real integration

- `templates/web/src/main.ts` rewritten as Workers entrypoint with full `Env` type (D1 / RATE_LIMIT_KV / IDEMPOTENCY_KV / BackupBucket / SENTRY_DSN / etc.).
- `templates/web/src/interfaces/http/app.ts` wires production middleware in the canonical order: `requestLogger → secureHeaders (with explicit CSP/COOP/CORP/Permissions-Policy) → strictCors → idempotency → routes`.
- `templates/web/src/interfaces/http/routes/health.ts` exposes `/healthz`, `/livez`, `/readyz` (with D1 ping), plus legacy `/health`.
- `templates/web/src/infrastructure/logging/pino-logger.ts` — pino factory with redact for `authorization` / `cookie` / `*.password` / `*.token`.
- `templates/db/d1/src/db/schema.ts` adds the `audit_log` table (indexed by actor + action) referenced by `rules/production.md`.
- `templates/db/d1/drizzle/0001_production_tables.sql` initial migration including `users`, `password_reset_tokens`, and `audit_log`.
- `templates/db/d1/wrangler.jsonc` (new JSON variant) declares **all** bindings: D1 (`DB`), KV (`RATE_LIMIT_KV`, `IDEMPOTENCY_KV`), R2 (`BackupBucket`) per dev / stage / prod environments.
- `templates/web/alchemy.run.ts` declares the Alchemy v2 stack (D1 + 2× KV + R2 + Worker).
- `templates/web/tests/load/smoke.js` — k6 baseline (p95 < 500 ms, error < 1 %).
- `templates/web/lighthouserc.json` — Lighthouse CI budgets (perf ≥ 0.85, a11y ≥ 0.95).

### Added — harness self-CI (`.github/workflows/`)

The plugin repo had no CI of its own. New `lint.yml` runs:
- `bash -n` on every script (scripts / skills / tests)
- shellcheck (warning level) on the same set
- `bash tests/spawn-lane-decision.sh` smoke test
- `tsc --noEmit` on `templates/web/src/` against pinned deps

Catches regressions before they hit users via `/plugin marketplace update`.

### Changed — middleware layout follows Clean Architecture

5.0/5.1 placed middleware at `templates/backend/hono/middleware/`, lib at
`templates/backend/hono/lib/`. That broke the existing `templates/web/src/`
layered structure and would have shipped to `dev/src/middleware/` instead
of the canonical layered location. 5.2.0 moves everything into the right
layer:

| 5.1 path | 5.2 path |
|---|---|
| `templates/backend/hono/middleware/security-headers.ts` | (deleted — uses built-in `hono/secure-headers` with options) |
| `templates/backend/hono/middleware/cors.ts` | `templates/web/src/interfaces/http/middleware/cors.ts` |
| `templates/backend/hono/middleware/rate-limit.ts` | `templates/web/src/interfaces/http/middleware/rate-limit.ts` |
| `templates/backend/hono/middleware/idempotency.ts` | `templates/web/src/interfaces/http/middleware/idempotency.ts` |
| `templates/backend/hono/middleware/logger.ts` | `templates/web/src/interfaces/http/middleware/request-logger.ts` |
| `templates/backend/hono/routes/health.ts` | (merged into `templates/web/src/interfaces/http/routes/health.ts`) |
| `templates/backend/hono/lib/sentry.cloudflare.ts` | `templates/web/src/infrastructure/monitoring/sentry.cloudflare.ts` |
| `templates/backend/hono/lib/sentry.node.ts` | (deleted — Workers-only stack) |
| `templates/backend/hono/lib/audit-log.ts` | `templates/web/src/infrastructure/audit/audit-log.ts` |
| `templates/backend/hono/lib/feature-flag.ts` | `templates/web/src/infrastructure/feature-flags/feature-flag.ts` |
| (no pino factory) | `templates/web/src/infrastructure/logging/pino-logger.ts` |

`templates/backend/` is removed entirely.

### Fixed — duplicate workflow distribution

`scripts/lib/distribute-production.sh` was copying the CI workflows that
`scripts/setup-common.sh` already distributes via `cp_glob_if_missing`. Now
the production-distribute helper handles **only** the runbooks (which
`templates/docs/runbooks/` is exclusively responsible for).

### Fixed — `sbom.yml` for pnpm

Switched from `@cyclonedx/cyclonedx-npm` (npm-only) to `@cyclonedx/cdxgen`
which auto-detects pnpm / yarn / bun.

### Fixed — `generate-package-json.sh` deps

- Adds `@sentry/cloudflare` to deps when `USE_WEB=yes`.
- Adds `alchemy`, `effect`, `@effect/platform-bun` to devDeps.
- Removes `@hono/node-server` (Workers-target).
- `dev` script: `tsx watch src/main.ts` → `wrangler dev`.

### Documentation

- `docs/PRODUCTION.md` — every path updated for the new layout, plus new rows for `wrangler.jsonc`, `alchemy.run.ts`, k6, Lighthouse, and `audit_log` schema.
- `rules/production.md` — paths corrected.

## [5.1.0] — 2026-05-11

Refactor pass on top of 5.0.0. No behaviour change; the harness now has a
cleaner internal API, faster TS templates, and tighter docs.

### Refactored — internal libraries (shared by ≥ 2 callers)

- `scripts/lib/memory-probe.sh` — single source of truth for `detect_total_ram_gb` / `detect_avail_ram_mb` / `detect_swap_total_gb` / `detect_swap_used_mb` / `detect_compressor_mb` / `detect_pressure`. `spawn-lane-decision.sh`, `recommend-lanes.sh`, and `doctor.sh` all source it (previously duplicated probe code across three files).
- `scripts/lib/rsync-excludes.sh` — wired into `bootstrap.sh` (was dead code in 5.0.0). The harness self-copy now goes through `harness_rsync`; patterns are edited in one place.
- `scripts/lib/distribute-production.sh` — production-template distribution extracted from `bootstrap.sh` to its own sourced library (`distribute_production_templates`).

### Refactored — bootstrap.sh

- New `copy_if_absent <src-glob> <dst-dir>` helper consolidates the five near-identical loops that distribute runbooks / CI workflows / Renovate / Dependabot / Hono middleware. Generated projects keep user-edited files (non-destructive).

### Refactored — doctor.sh

- `RESULTS` accumulator: string-parsing → three parallel bash arrays (`KINDS` / `NAMES` / `MSGS`). Removes a fragile pipe-into-while-IFS read.
- `--json` output: hand-rolled `sed`-based escaping → proper `jq -n --arg` construction. Now correctly handles backslash / newline / control chars in messages.

### Refactored — Hono templates

- `lib/audit-log.ts` — DB-specific `DrizzleD1Database` dependency removed. New `AuditWriter` adapter contract with a `drizzleAuditWriter(db, sql)` factory works against any Drizzle dialect (D1 / Postgres / MySQL / SQLite).
- `lib/sentry.ts` → `lib/sentry.cloudflare.ts` + `lib/sentry.node.ts`. Workers and Node/Bun deployments each get a focused helper without conditional bundling tricks.
- `lib/feature-flag.ts` — `parse(env)` result is now memoized in a `WeakMap` keyed by the env object. Removes the per-call parse cost.

## [5.0.0] — 2026-05-11

**Production-grade rebuild.** The harness now scaffolds projects that can ship
to production with full controls. Every concern that's hard to retrofit (security
headers, rate limiting, structured logging with request-id propagation,
idempotency, health endpoints, Sentry, audit log, feature flags, CodeQL,
SBOM, license audit, k6, Lighthouse, Renovate, Dependabot, six runbooks)
is wired in at `bootstrap.sh` time and enforced by `rules/production.md`.

### Added — production scaffold

- **Hono middleware suite** in `templates/backend/hono/`:
  `security-headers.ts` (CSP/HSTS/XFO/COOP/CORP/Permissions-Policy),
  `rate-limit.ts` (KV-backed token-bucket per-bucket: login / password-reset / api),
  `logger.ts` (pino + `x-request-id` propagation, redacts authorization / cookie / password),
  `idempotency.ts` (`Idempotency-Key` 24 h KV cache),
  `cors.ts` (allowlist from `ALLOWED_ORIGINS`, no `*`).
- **Health endpoints** (`templates/backend/hono/routes/health.ts`):
  `/healthz` / `/readyz` (DB ping + smoke checks) / `/livez`.
- **Lib helpers**: `sentry.ts` (`@sentry/cloudflare` Workers init),
  `audit-log.ts` (append-only `audit_log` table), `feature-flag.ts`
  (env-var driven with stable-hash % rollout).
- **CI workflows**: `codeql.yml` (PR + weekly), `sbom.yml` (CycloneDX on
  release), `license-check.yml` (fail on GPL/AGPL/SSPL/SSPL),
  `k6-smoke.yml` (PR → stage), `lighthouse.yml` (PR → main/stage).
- **Dependency automation**: `renovate.json` (grouped minor/patch,
  manual majors, beta-pin) + `dependabot.yml` (GH Actions ecosystem).
- **Runbooks** (`templates/docs/runbooks/`): `incident-response.md`,
  `deploy.md`, `rollback.md`, `dr-plan.md`, `oncall.md`,
  `postmortem.md` — required by `rules/production.md`'s pre-launch
  checklist.
- **`rules/production.md`** — single source of truth for production
  expectations (observability / security headers / rate limits / CORS /
  idempotency / health / audit log / backups / DR / dependencies /
  SAST/DAST / supply chain / runbooks / pre-launch checklist).
- **`docs/PRODUCTION.md`** — guide that maps each concern to its file
  in the generated project.

### Changed — OS-aware MAX_LANES recommendation

- New `scripts/lib/recommend-lanes.sh` accounts for **macOS memory
  compression** (+33 % effective RAM via `vm.compressor`) and live
  `memory_pressure -Q` (green/yellow/red), and Linux swap. The naive
  "TOTAL_RAM >= 24 GB → 4 lanes" rule was wrong: a 16 GB Mac in
  green pressure now correctly recommends 4 lanes.
- `bootstrap.sh` and `scripts/doctor.sh` both use the new lib.

### Added — harness operations

- `scripts/doctor.sh` — pre-flight diagnostics
  (bare repo / .config / MAX_LANES vs recommendation / required tools /
  Codex CLI auth / Codex daemon liveness / spawn-lane-decision dry-run /
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`).
  `--json` for machine-readable output.
- `scripts/prune-lanes.sh` — remove teammates whose lane number exceeds
  the current `MAX_LANES` from the team config (`--max <n>`,
  `--dry-run`). Resolves the "stale teammates after lowering MAX_LANES"
  pitfall.
- `scripts/lib/rsync-excludes.sh` — single source of truth for
  `dev/.my-harness/` rsync rules. Sourced by bootstrap and adopt-refresh.
- `tests/spawn-lane-decision.sh` — pure-bash smoke test (11 cases,
  no bats dependency) covering every REFUSE / SKIP / SPAWN path.

### Changed — `spawn-lane-decision.sh` cleanup

- Removed redundant hard-coded `1..4` validation (MAX_LANES is the
  ceiling). Invalid input is now caught generically (positive integer).
- `exceeds-max-lanes` reason now suggests `prune-lanes.sh` explicitly.

### Added — bootstrap distributes production templates

`bootstrap.sh` now copies, when applicable:

- `templates/docs/runbooks/*.md` → `dev/docs/runbooks/`
- `templates/github/workflows/{codeql,sbom,license-check,k6-smoke,lighthouse}.yml` → `dev/.github/workflows/`
- `templates/github/renovate.json` → `dev/renovate.json`
- `templates/github/dependabot.yml` → `dev/.github/dependabot.yml`
- `templates/backend/hono/{middleware,routes,lib}/*.ts` → `dev/src/{middleware,routes,lib}/`
  (only when `USE_BACKEND=yes` and `BACKEND_KIND=hono`)

All copies are non-destructive: existing files are kept.

### BREAKING

- Generated projects now expect `RATE_LIMIT_KV` and `IDEMPOTENCY_KV` KV
  bindings in `wrangler.jsonc` and `alchemy.run.ts`. Adopt these by
  rerunning `/harness-deploy` (setup mode adds the missing bindings).
- `dev/src/middleware/`, `dev/src/routes/health.ts`, `dev/src/lib/{sentry,audit-log,feature-flag}.ts`
  are now reserved paths owned by the harness; user code must not
  overwrite them. Rename your files if you previously claimed these
  paths.
- Adopted projects upgrading from 4.x: rerun `/my-harness-adopt` to
  receive the new templates and runbooks (refresh path is non-destructive
  on existing files).

## [4.7.0] — 2026-05-11

Comprehensive surface reduction and observability tighten-up.

### Configurable lane cap

- `MAX_LANES` (1..4, default 4) is now a first-class option in `.my-harness/.config`. `bootstrap.sh` asks for it at Setup; `spawn-lane-decision.sh` refuses lanes > MAX_LANES with reason `exceeds-max-lanes`. Lower this on tight machines without touching code.

### Skill / slash-command consolidation

- `/harness-deploy-setup` + `/harness-deploy-execute` collapsed into a single idempotent `/harness-deploy` (auto-detects mode from `dev/alchemy.run.ts` presence). Slash-command surface: 6 → 5 (`/my-harness-init`, `/my-harness-adopt`, `/harness-team-lead`, `/harness-deploy`, `/harness-codex-daemon`). Skill count: 6 → 5.

### Documentation consolidation

- Deleted `docs/SECURITY.md` — security policy merged into `docs/SETUP.md` (one place to look for "what do I configure once after creating the repo").
- Deleted `docs/ENGINEER_STANDARDS.md` — content was already mirrored by `rules/*.md` (the single source of truth).
- Deleted `templates/prs/` — zero references in the dispatch path.

### Prose compression

- `README.md`: 372 → ~190 lines (-49 %). Same content, less repetition.
- `README.ja.md`: 341 → ~180 lines (-47 %).
- `CHANGELOG.md`: pre-4.7 history collapsed to a one-line-per-version summary table.

### Misc

- `dev/.my-harness/` rsync now excludes `.git`, `node_modules`, `*.test.ts`, internal CHANGELOG / docs / README — only runtime assets ship to user projects.
- Stale `.harness/docs/ENGINEER_STANDARDS.md` reference in `templates/android/.../MainActivity.kt` updated to `.my-harness/rules/design.md`.

No behaviour change beyond the cap.

## Pre-4.7 history (summary)

| Version | Highlight |
|---|---|
| 4.6.0 | Removed 4 auxiliary slash commands replaceable by one-line manual ops (`/harness-branch-protection`, `/harness-check-codex-auth`, `/harness-check-secrets`, `/harness-setup-secrets`). Skill SKILL.md compression (`harness-codex-daemon`/`harness-deploy-setup`/`harness-deploy-execute` shrunk a combined 146 lines). |
| 4.5.0 | Semantic-preserving prose compression on the high-context-frequency files (agents/*, SKILL.md, rules/*) — 1560 → 1274 lines (-18 %). No rule body / status enum / bash command changed. |
| 4.4.0 | `/my-harness-update` folded into `/my-harness-adopt` (branches on `.bare/` presence). Removed 8 thin-wrapper rule skills — bodies live in `rules/*.md` and are loaded by `dev/CLAUDE.md` / `dev/AGENTS.md` / agents / `codex-ask.sh --role`. |
| 4.3.0 | Dropped 10 unused scripts, 6 thin-wrapper skills, 1 niche workflow template. Stripped all TEST-LOG debug blocks (superseded by 4.1.0 logging). CHANGELOG / README / plugin descriptions rewritten for the 4.x architecture. |
| 4.2.0 | `/my-harness-update` skill — idempotent counterpart of `/my-harness-adopt` for plugin upgrades. (Folded into adopt in 4.4.0.) |
| 4.1.0 | Observability + auto-intervention: per-teammate `agent-log.sh`, `monitor-agents.sh` view + `--watchdog` mode, anomaly classification (stagnation / repeated-blocked / codex-exec-failure / codex-no-op / suffixed-name), lead Step 3.0 deterministic intervention. Fixed BSD `date -j -f` timezone bug (`-ujf`). |
| 4.0.0 (BREAKING) | True Codex delegation. `codex-exec.sh` performs real file edits inside lane worktrees; engineer / reviewer Claude become monitors. `analyst` gains `USE_CODEX_ANALYST`. New status `blocked-codex-error`. |
| 3.10.0 | `rules/` became the single source of truth shared across Claude and Codex; `dev/CLAUDE.md` + `dev/AGENTS.md` reference `rules/*.md`; `codex-ask.sh` auto-attaches the same files via `--context`. |
| 3.9.x | `codex-ask.sh` absolute path; `owned_files` as dispatch hint; engineer hard rules + `blocked-workspace-not-ready`; drop `start-dev.sh` launcher; `/my-harness-adopt` for existing-repo conversion. |
| 3.8.x | Parallel dispatch with sequential spawn; root-resolution from any cwd; vendor-neutral cleanup; lane-by-lane spawn gate + name-collision guard. |
| 3.0 – 3.7 | Iterative kernel-panic-prevention path (preflight gate, lane-lock, devshell wrapper, content-hash cache, task lifecycle, worktree management). Largely subsumed by 3.8+. |
| 2.x | Agent Teams architecture (4 lanes × 4 roles persistent teammates); shared Codex daemon; Cloudflare IaC moved from OpenTofu to Alchemy v2. |
| 1.0.0 | Initial plugin release: skills + agents + hooks + secret masking. |
