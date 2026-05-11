# Changelog

All notable changes documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [5.0.0] — 2026-05-11

**Production-grade rebuild.** The harness now scaffolds projects that can ship
to production, not just MVPs. Every concern that's hard to retrofit (security
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
