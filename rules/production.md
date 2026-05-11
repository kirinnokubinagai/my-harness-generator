# Production-grade requirements

The harness ships scaffolding for production use. The list below is what an MVP
must add before being called "production-ready". Each item is wired by
`bootstrap.sh` when applicable; the team is responsible for keeping it healthy.

## Observability

- Structured logging (pino) with **request-id propagation** at every layer.
  Request id arrives via `x-request-id` header (or generated), echoed back in
  the response, and stamped on every log line.
- Error tracking (Sentry or equivalent) with source-maps uploaded at deploy.
- Metrics: at minimum p95 latency / error-rate / RPS / DB-query-time per
  endpoint. Cloudflare Analytics Engine is the default sink for Workers.
- Dashboards: one "service health" dashboard per service, surfaced in
  `dev/docs/runbooks/oncall.md`.
- SLOs: each user-facing endpoint declares an availability target and a
  latency target. Breaches page the on-call.

## Security headers (mandatory on every HTTP response)

- `Content-Security-Policy` — start at `default-src 'self'`; widen only with
  explicit origins.
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`.
- `X-Frame-Options: DENY` (or `frame-ancestors` in CSP).
- `X-Content-Type-Options: nosniff`.
- `Referrer-Policy: strict-origin-when-cross-origin`.
- `Permissions-Policy` — explicit deny for `geolocation` / `microphone` /
  `camera` / `payment` unless used.
- `Cross-Origin-Opener-Policy: same-origin`,
  `Cross-Origin-Resource-Policy: same-site`.

Wired by `hono/secure-headers` (with explicit options) in `dev/src/interfaces/http/app.ts`.

## Rate limiting (mandatory)

- Login: 5 / 15 min per IP + per account.
- Password reset: 3 / hour per email.
- Generic API: 100 / 15 min per IP authenticated, 30 / 15 min unauthenticated.
- Use Cloudflare Rate Limiting binding when on Workers; fall back to KV-based
  counter (`dev/src/interfaces/http/middleware/rate-limit.ts`).

## CORS (no wildcard ever)

- Allowlist read from `ALLOWED_ORIGINS` env var (comma-separated).
- `credentials: true` requires explicit origin echo.
- Preflight `OPTIONS` must short-circuit (no auth check).

## Idempotency

State-changing endpoints (POST / PUT / PATCH / DELETE) honour an
`Idempotency-Key` header. Replays within 24 h return the cached response.
Wired by `dev/src/interfaces/http/middleware/idempotency.ts` (KV-backed).

## Health endpoints

- `GET /healthz` — process is up. Returns `200 {"ok": true}`. No DB call.
- `GET /readyz` — process can serve traffic. Returns `200` only when DB,
  cache, and external dependencies pass a smoke check. `503` otherwise.
- `GET /livez` — alias of `/healthz` for Kubernetes-style probes.

## Audit log

- Separate table (or stream) — `audit_log(actor_id, action, resource,
  metadata, occurred_at)`. Append-only.
- Retention ≥ 1 year.
- Write helper: `dev/src/infrastructure/audit/audit-log.ts`.
- Required for: auth events / permission change / data deletion / admin
  actions / billing events.

## Backups + restore

- `templates/github/workflows/scheduled-db-backup.yml` runs nightly:
  `pg_dump` (or `wrangler d1 export`) → `age` encrypt → R2 upload.
- **Restore must be tested at least quarterly.** Untested backups are not
  backups. Drill is documented in `dev/docs/runbooks/dr-plan.md`.

## Disaster recovery

- RTO (recovery time objective) and RPO (recovery point objective) per
  service, declared in `dev/docs/runbooks/dr-plan.md`.
- Multi-region or multi-AZ where the SLA demands it.

## Dependencies

- `renovate.json` ships at bootstrap. Group minor/patch; pin majors.
- `dependabot.yml` enabled for security alerts (complements Renovate).
- Weekly `npm audit` / `pnpm audit` / `cargo audit` in CI.

## SAST / DAST

- CodeQL (`.github/workflows/codeql.yml`) on every PR + weekly on `main`.
- Semgrep (OWASP TS ruleset) on PR → `dev`.
- Trivy (deps + container) on PR + scheduled.
- OWASP ZAP baseline + full on `dev` → `stage`.
- gitleaks pre-commit + CI history scan.

## Supply chain

- SBOM (`cyclonedx-bom`) generated on every release, attached to the GitHub
  Release.
- License audit (`license-checker`) on every release; fail on
  GPL/AGPL/SSPL unless explicitly allow-listed.

## Runbooks (must exist before launch)

| File | Owner | Required content |
|---|---|---|
| `dev/docs/runbooks/incident-response.md` | on-call | severity matrix, comms, escalation |
| `dev/docs/runbooks/deploy.md` | release captain | dev → stage → main steps + rollback |
| `dev/docs/runbooks/rollback.md` | on-call | `git revert` flow + canary roll-back |
| `dev/docs/runbooks/dr-plan.md` | SRE | RTO / RPO / restore drill schedule |
| `dev/docs/runbooks/oncall.md` | on-call | rotation, paging, dashboards, common alerts |
| `dev/docs/runbooks/postmortem.md` | author | blameless template (5-whys + action items) |

## Production checklist before first launch

- [ ] All seven runbooks exist and have been read by the on-call team
- [ ] Backup restore drill executed in the last 90 days
- [ ] Sentry receiving events from production (intentional test event verified)
- [ ] OWASP ZAP full scan on stage: zero high / critical findings
- [ ] Load test against stage demonstrates ≥ 2× expected peak
- [ ] CSP report-only deployed, then enforced after 7 days clean
- [ ] Rate limiting verified against synthetic abuse
- [ ] At least one chaos drill (kill DB, kill region, kill dependency) executed
- [ ] On-call rotation populated and paging tested
- [ ] Audit log retention confirmed (1 y) and access-controlled
- [ ] Privacy policy + ToS published; cookie banner if EU users
