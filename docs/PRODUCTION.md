# Production guide

This harness produces **production-grade** scaffolds. The defaults below are
wired by `bootstrap.sh` and enforced by `rules/production.md`. None of the
items are optional for production use; the harness installs them at bootstrap
so they cannot be forgotten later.

## What you get out of the box

| Concern | Where it lives | Notes |
|---|---|---|
| Security headers (CSP/HSTS/XFO/COOP/CORP/Permissions-Policy) | `dev/src/interfaces/http/app.ts` | `hono/secure-headers` with explicit options |
| Rate limiting (KV-backed) | `dev/src/interfaces/http/middleware/rate-limit.ts` | Per-bucket: login / password-reset / api |
| Structured logging (pino) + request-id | `dev/src/interfaces/http/middleware/request-logger.ts` + `dev/src/infrastructure/logging/pino-logger.ts` | `c.get('logger')` in every layer |
| CORS allowlist (no `*`) | `dev/src/interfaces/http/middleware/cors.ts` | Reads `ALLOWED_ORIGINS` env |
| Idempotency (`Idempotency-Key`) | `dev/src/interfaces/http/middleware/idempotency.ts` | 24 h KV cache for POST/PUT/PATCH/DELETE |
| Health endpoints (`/healthz` `/readyz` `/livez`) | `dev/src/interfaces/http/routes/health.ts` | `/readyz` runs DB ping |
| Sentry init (Workers) | `dev/src/infrastructure/monitoring/sentry.cloudflare.ts` | `withSentry(app, env)` wrap |
| Audit log helper | `dev/src/infrastructure/audit/audit-log.ts` | Append-only `audit_log` table |
| Feature flags | `dev/src/infrastructure/feature-flags/feature-flag.ts` | Env-var driven (% rollout via stable hash) |
| Workers config | `dev/wrangler.jsonc` | D1 + KV (RATE_LIMIT_KV, IDEMPOTENCY_KV) + R2 (BackupBucket) bindings |
| Alchemy stack | `dev/alchemy.run.ts` | One-shot infra: D1 + 2× KV + R2 + Worker |
| k6 smoke | `dev/tests/load/smoke.js` | PR → stage baseline (p95 < 500 ms, error < 1 %) |
| Lighthouse | `dev/lighthouserc.json` | perf ≥ 0.85, a11y ≥ 0.95, best-practices ≥ 0.90 |
| audit_log table | `dev/src/db/schema.ts` + `dev/drizzle/0001_production_tables.sql` | Append-only, indexed by actor + action |
| CodeQL SAST | `dev/.github/workflows/codeql.yml` | PR + weekly |
| SBOM (CycloneDX) | `dev/.github/workflows/sbom.yml` | On release |
| License audit | `dev/.github/workflows/license-check.yml` | Fails on GPL/AGPL/SSPL |
| k6 smoke | `dev/.github/workflows/k6-smoke.yml` | PR → stage |
| Lighthouse CI | `dev/.github/workflows/lighthouse.yml` | PR → main/stage |
| Renovate | `dev/renovate.json` | Grouped minor/patch, manual majors |
| Dependabot | `dev/.github/dependabot.yml` | GH Actions ecosystem |

## Runbooks

`dev/docs/runbooks/` is populated at bootstrap with:

- `incident-response.md` — severity matrix, roles, comms cadence
- `deploy.md` — dev → stage → main + canary
- `rollback.md` — decision tree, fast-path canary reset, slow-path revert
- `dr-plan.md` — RTO / RPO, risk inventory, restore drill
- `oncall.md` — rotation, dashboards, common alerts
- `postmortem.md` — blameless template

Edit them; do not delete. Each one is required by `rules/production.md`'s
launch checklist.

## Configuration

The interview asks 8 questions that map directly onto production controls
(beyond the standard tool/framework choices):

| Question | Effect on production |
|---|---|
| `MAX_LANES` | Caps parallel agent lanes (runtime gate refuses spawns when free RAM / swap / compressor are tight) |
| `USE_CODEX_*` | Per-role Codex delegation. Roles fall back to Claude on `subscription-or-quota` |
| `ON_CODEX_AUTH_FAIL` | `pause` (wait for re-login) or `fail` (hard fail) |
| `USE_GITHUB_ISSUES` | Drives whether Renovate / Dependabot file issues or only PRs |
| `USE_GLOBAL_CLAUDE` | `no` isolates `dev/` from your global `~/.claude/CLAUDE.md` |

## Pre-launch checklist

See `rules/production.md` — every item must be checked before calling the
service production-ready. Highlights:

- [ ] Backup restore drill executed in the last 90 days (`runbooks/dr-plan.md`)
- [ ] Sentry receiving events from production
- [ ] OWASP ZAP full scan on stage: zero high/critical findings
- [ ] Load test on stage ≥ 2× expected peak
- [ ] CSP report-only deployed for 7 days clean before enforcement
- [ ] At least one chaos drill executed (DB / region / dependency kill)
- [ ] On-call rotation populated and paging tested

## Sane defaults you can change

| Default | Why | When to change |
|---|---|---|
| 4 lanes hard cap | Agent Teams beyond that → diminishing returns | Don't (raise `MAX_LANES` ceiling per host instead) |
| 4 GB / lane gate | Empirical Claude Code working set | Lower with `HARNESS_LANE_RAM_MB` on low-RAM hosts |
| `pino` log level `info` | Balance signal/noise | `debug` during investigation |
| `tracesSampleRate: 0.1` | Sentry cost control | Raise during incidents |
| 24 h idempotency TTL | RFC draft norm | Lower if KV storage costs matter |
| 100 / 15 min API rate | Stripe-ish default | Tune per business model |

## Observability stack

- **Logs**: pino → CloudWatch / Datadog / Axiom (sink configured in worker env)
- **Errors**: Sentry (`@sentry/cloudflare`)
- **Metrics**: Cloudflare Analytics Engine (built-in)
- **Traces**: OpenTelemetry exporter via `@microlabs/otel-cf-workers` (opt-in)

## Beyond 5.0.0

The harness covers what's hard to retrofit. These remain on you:

- Domain modelling (we just bootstrap the migration tooling)
- Customer comms (status page provisioning, ToS / Privacy Policy text)
- Multi-region failover testing
- Chaos engineering scenarios specific to your domain
- Compliance audits (SOC 2 / ISO 27001 / HIPAA / PCI)

The runbook templates leave room for your specifics — fill them in early.
