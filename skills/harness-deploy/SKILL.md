---
name: harness-deploy
description: Combined deploy entry point — idempotent. On first run (no `dev/alchemy.run.ts` yet) it generates the Alchemy v2 infrastructure script and sets up Cloudflare / GitHub Secrets / wrangler / fastlane. On subsequent runs it executes the staged dev → stage → main pipeline (OWASP ZAP / Playwright / Maestro on stage, human approval + canary 10% → 100% on main). Fires when the user says "deploy", "release", "promote to stage", "push to production", "deploy setup", "IaC with Alchemy", or similar.
---

# harness-deploy

Single entry point for deployment. Auto-detects mode from `<root>/dev/alchemy.run.ts`:

| State | Mode | What runs |
|---|---|---|
| `dev/alchemy.run.ts` absent | **setup** | Build the Alchemy v2 infrastructure script and the surrounding secrets / wrangler / TestFlight setup |
| `dev/alchemy.run.ts` present | **execute** | Stage releases dev → stage → main with the existing pipeline |

The user can force setup re-run with the explicit `setup` argument.

```bash
# Auto-detect:
/harness-deploy
# Force setup:
/harness-deploy setup
```

---

## MODE: setup (first-time infra creation)

Builds the **infrastructure + secrets** for the dev → stage → main pipeline using **Alchemy v2 (TypeScript-native IaC on Effect.ts)**.

Cloudflare Pages is **out of scope** — use `Cloudflare.Worker` + Workers Static Assets for static sites. Alchemy v2 is `2.0.0-beta.x` (Effect v4); pin the exact version and update intentionally.

### Prerequisites

- `.my-harness/.config` finalized (`USE_DB`, `USE_EMAIL`, etc. set).
- Repo pushed to GitHub (`gh repo view` succeeds).
- Branch protection applied once: `bash scripts/setup-branch-protection.sh <owner>/<repo>` (or `gh api ...`).
- Bun in the Nix shell (from `templates/nix/flake.nix`).

### Steps

**1. Install Alchemy v2** (in `<root>/dev`):
```bash
nix develop --command bun add alchemy effect @effect/platform-bun @effect/platform-node
nix develop --command bun add -d @cloudflare/workers-types
```
Pin `alchemy` to a specific beta in `package.json` (e.g. `"alchemy": "2.0.0-beta.36"`).

**2. Generate `dev/alchemy.run.ts`** from `.my-harness/.config`. Single source of truth; no secrets inside.

```typescript
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Effect from "effect/Effect";

export default Alchemy.Stack(
  "harness",
  { providers: Cloudflare.providers(), state: Cloudflare.state() },
  Effect.gen(function* () {
    // STAGE from --stage <name> or env STAGE; each stage isolated.

    const db = yield* Cloudflare.D1Database("Db", {
      name: `harness-${process.env.STAGE ?? "dev"}`,
      // adopt: true,  // import an existing D1 of the same name
    });

    const backupBucket = yield* Cloudflare.R2Bucket("BackupBucket", {
      name: `harness-${process.env.STAGE ?? "dev"}-backups`,
    });

    const worker = yield* Cloudflare.Worker("Api", {
      main: "./src/worker.ts",
      url: true,
      bindings: { Db: db, BackupBucket: backupBucket },
    });

    // USE_EMAIL=yes → add SPF / DKIM / DMARC via Cloudflare.DnsRecords.

    return { worker_url: worker.url, d1_id: db.id, bucket: backupBucket.name };
  }),
);
```

**3. Register GitHub Actions secrets**:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-secrets.sh <owner>/<repo>
```
Required: `CLOUDFLARE_API_TOKEN` (Workers / D1 / R2 / KV) + `CLOUDFLARE_ACCOUNT_ID`. **Never** put these in `alchemy.run.ts`.

**4. Local Alchemy auth** (developer machines):
```bash
nix develop --command bunx alchemy login --configure
# Cloudflare → paste token + account ID; save as profile "dev"
# bunx alchemy login --profile prod --configure  for prod
```
Profiles at `~/.alchemy/profiles.json` (do not commit). For SOPS-encrypted credentials, decrypt then export `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` before invoking Alchemy.

**5. Hand-write `dev/wrangler.jsonc`** (Alchemy does not generate it; used by `wrangler d1 migrations apply`):
```jsonc
{
  "name": "harness",
  "main": "src/worker.ts",
  "compatibility_date": "2025-05-01",
  "d1_databases": [
    { "binding": "Db", "database_name": "harness-dev", "database_id": "<from alchemy state get harness dev Db>" }
  ],
  "env": {
    "stage": { "d1_databases": [{ "binding": "Db", "database_name": "harness-stage", "database_id": "<...>" }] },
    "prod":  { "d1_databases": [{ "binding": "Db", "database_name": "harness-prod",  "database_id": "<...>" }] }
  }
}
```
Pull real D1 ids after first deploy: `nix develop --command bunx alchemy state get harness dev Db | jq -r .id`.

**6. First deploy** (creates Cloudflare resources):
```bash
nix develop --command bunx alchemy plan --stage dev
nix develop --command bunx alchemy deploy --stage dev --yes
```
Repeat for `--stage stage` after Step 5 is verified. Never auto-deploy `--stage prod` from a dev machine — that's the execute path below (via CI).

**7. Verify** the Worker URL, `wrangler d1 migrations apply Db --env stage --remote`, R2 `put` / `get`, and `bunx alchemy state tree`.

### Adopting existing Cloudflare resources

`nix develop --command bunx alchemy deploy --stage prod --adopt`, or `adopt: true` per-resource in `alchemy.run.ts`.

### Setup done checklist

- [ ] `dev/alchemy.run.ts` committed (no secrets inside)
- [ ] `package.json` pins `alchemy` to a specific beta
- [ ] `bunx alchemy plan --stage dev` produces a clean diff
- [ ] D1 / R2 / Worker created in the Cloudflare dashboard
- [ ] `dev/wrangler.jsonc` populated with real D1 ids
- [ ] `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` in GitHub Secrets
- [ ] `DEPLOY_READY=yes` appended to `.my-harness/.config`

---

## MODE: execute (staged release)

Stages releases dev → stage → main. All features must be merged to `dev` and CI green.

### A. dev → stage (automated, human-approved)

```bash
git checkout stage
git fetch origin
gh pr create --base stage --head dev --title "release: dev → stage <date>"
```

`pr-to-stage.yml` runs quality (biome / vitest / tsc), e2e (Playwright + Maestro), security (OWASP ZAP + MobSF + history gitleaks). Green CI alone is **not** enough — the `approved-for-stage` label is required. CI failures auto-file an issue via `maybe-create-issue.js`.

```bash
gh pr review <pr-number> --approve
gh pr edit <pr-number> --add-label approved-for-stage
gh pr merge <pr-number> --auto --merge
```

After the merge, stage deploys automatically: Cloudflare Pages picks up `stage`, `wrangler d1 migrations apply DB --env staging --remote` runs, R2 backups can be restored manually (`wrangler r2 object get` + `wrangler d1 execute`), TestFlight upload runs when `USE_IOS=yes`.

### B. stage → main (after 24h+ stable on stage)

Verify 24+ h stable run on staging: metrics (p95 / error rate / auth failures) clean; ZAP / E2E green.

```bash
gh release create vX.Y.Z --draft --generate-notes --target stage
gh pr create --base main --head stage \
  --title "release: stage → main vX.Y.Z" \
  --body-file .github/release-pr-body.md
gh pr edit <pr-number> --add-label approved-for-prod
gh pr merge <pr-number> --auto --merge
```

`pr-to-main.yml` re-runs all gates and verifies `approved-for-prod`.

### C. Canary 10% → 100%

```bash
nix develop --command pnpm exec wrangler deployments deploy --env production --percent 10
# 30 min at 10% → check
nix develop --command bash .my-harness/scripts/check-canary-health.sh
# if healthy:
nix develop --command pnpm exec wrangler deployments deploy --env production --percent 100
gh release edit vX.Y.Z --draft=false
```

### Rollback

Use `git revert` only (rebase / reset / force-push prohibited per `rules/` and `docs/HOTFIX.md`):

```bash
git checkout main
git revert -m 1 <merge-sha>
git push origin main
```

Or roll the canary back: `nix develop --command pnpm exec wrangler rollback <previous-deployment-id>`.

### Emergency fixes

Follow `docs/HOTFIX.md`: branch `hotfix/<short>` from `main`, PR target `main`, merge-commit back to `stage` and `dev`.

### Execute done checklist

**dev → stage**
- [ ] CI on dev green
- [ ] PR `--base stage --head dev`
- [ ] OWASP ZAP / Playwright / Maestro green
- [ ] `approved-for-stage` applied (human)
- [ ] Stage merged via auto-merge

**stage → main**
- [ ] 24+ h stable on stage; metrics clean
- [ ] `gh release create --draft` done
- [ ] `approved-for-prod` applied
- [ ] Main merged via auto-merge

**Canary**
- [ ] 10% for 30 min, metrics clean
- [ ] Promoted to 100%
- [ ] `gh release edit --draft=false` done

---

## Related

- Hotfix procedure: `docs/HOTFIX.md`
- Git discipline: `rules/nix-pure.md` + `docs/HOTFIX.md`
- Secrets: `scripts/setup-secrets.sh` + `docs/SETUP.md`
- Infrastructure details: `docs/INFRA.md`
- No-hardcode policy: `rules/no-hardcoded-secrets.md`
