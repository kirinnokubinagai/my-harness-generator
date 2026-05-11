---
name: harness-deploy-setup
description: Defines deploy infrastructure with Alchemy v2 (Effect.ts) and sets up Cloudflare (Workers / R2 / D1 / KV / DNS / Tunnel), GitHub Actions secrets, wrangler, and fastlane (iOS) in one pass. Generates `dev/alchemy.run.ts` (Effect.gen + yield* per Alchemy v2 syntax) and the corresponding stage configuration. Fires when implementation is complete and the next step is deployment: "deploy setup", "IaC with Alchemy", "Cloudflare setup", "initial deploy prep", or similar.
---

# harness-deploy-setup

Builds the **infrastructure + secrets** for the dev → stage → main pipeline using **Alchemy v2 (TypeScript-native IaC on Effect.ts)**. Run once after implementation, before the first deploy.

Cloudflare Pages is **out of scope** — use `Cloudflare.Worker` + Workers Static Assets if you need a static site. Alchemy v2 is `2.0.0-beta.x` (Effect v4); pin the exact version and update intentionally.

## Prerequisites

- `.my-harness/.config` finalized (`USE_DB`, `USE_EMAIL`, etc. set).
- Repo pushed to GitHub (`gh repo view` succeeds).
- Branch protection applied once manually: `bash scripts/setup-branch-protection.sh <owner>/<repo>` (or `gh api ...`).
- Bun in the Nix shell (from `templates/nix/flake.nix`).

## Steps

### 1. Install Alchemy v2 (in `<root>/dev`)

```bash
nix develop --command bun add alchemy effect @effect/platform-bun @effect/platform-node
nix develop --command bun add -d @cloudflare/workers-types
```

Pin `alchemy` to a specific beta in `package.json` (e.g. `"alchemy": "2.0.0-beta.36"`).

### 2. Generate `dev/alchemy.run.ts` from `.my-harness/.config`

Single source of truth for Cloudflare infrastructure. Do not put secrets in this file — they live in env vars (Step 4).

```typescript
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Effect from "effect/Effect";

export default Alchemy.Stack(
  "harness",
  {
    providers: Cloudflare.providers(),
    state: Cloudflare.state(),     // remote state in Cloudflare DO
  },
  Effect.gen(function* () {
    // STAGE comes from --stage <name> or env STAGE; each stage is isolated.

    // D1 (USE_DB=yes && DB_KIND=d1)
    const db = yield* Cloudflare.D1Database("Db", {
      name: `harness-${process.env.STAGE ?? "dev"}`,
      // adopt: true,  // import an existing D1 by the same name
    });

    // R2 backup bucket
    const backupBucket = yield* Cloudflare.R2Bucket("BackupBucket", {
      name: `harness-${process.env.STAGE ?? "dev"}-backups`,
    });

    // KV (optional)
    // const kv = yield* Cloudflare.KVNamespace("Kv", { title: "harness-kv" });

    // Worker (USE_WEB=yes normally renders into a Worker + Assets)
    const worker = yield* Cloudflare.Worker("Api", {
      main: "./src/worker.ts",
      url: true,
      bindings: { Db: db, BackupBucket: backupBucket /*, Kv: kv*/ },
    });

    // DNS records (USE_EMAIL=yes → add SPF / DKIM / DMARC)
    // const zone = yield* Cloudflare.Zone("ApexZone", { name: "example.com" });
    // yield* Cloudflare.DnsRecords("EmailDns", { zone, records: [ ... ] });

    return { worker_url: worker.url, d1_id: db.id, bucket: backupBucket.name };
  }),
);
```

### 3. Register GitHub Actions secrets

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-secrets.sh <owner>/<repo>
```

Required for Alchemy v2 + Cloudflare:
- `CLOUDFLARE_API_TOKEN` (Workers / D1 / R2 / KV permissions)
- `CLOUDFLARE_ACCOUNT_ID`

Alchemy reads these at deploy time. **Never** put them in `alchemy.run.ts`.

### 4. Local Alchemy auth (developer machines)

```bash
nix develop --command bunx alchemy login --configure
# Pick "Cloudflare", paste API token + account ID, save as profile "dev"
# For prod: bunx alchemy login --profile prod --configure
```

Profiles live at `~/.alchemy/profiles.json` (plain JSON, do not commit). For SOPS-encrypted credentials:

```bash
nix develop --command sh -c '
  export CLOUDFLARE_API_TOKEN=$(sops -d secrets/cloudflare.enc.json | jq -r .api_token)
  export CLOUDFLARE_ACCOUNT_ID=$(sops -d secrets/cloudflare.enc.json | jq -r .account_id)
  bunx alchemy deploy --stage dev
'
```

### 5. Hand-write `dev/wrangler.jsonc` (Alchemy does not generate it)

Used by `wrangler d1 migrations apply`:

```jsonc
{
  "name": "harness",
  "main": "src/worker.ts",
  "compatibility_date": "2025-05-01",
  "d1_databases": [
    { "binding": "Db", "database_name": "harness-dev",   "database_id": "<from alchemy state get harness dev Db>" }
  ],
  "env": {
    "stage": { "d1_databases": [{ "binding": "Db", "database_name": "harness-stage", "database_id": "<...>" }] },
    "prod":  { "d1_databases": [{ "binding": "Db", "database_name": "harness-prod",  "database_id": "<...>" }] }
  }
}
```

Pull the real D1 ids after the first deploy:

```bash
nix develop --command bunx alchemy state get harness dev Db | jq -r .id
```

### 6. First deploy (creates Cloudflare resources)

```bash
nix develop --command bunx alchemy plan --stage dev
nix develop --command bunx alchemy deploy --stage dev --yes
```

Repeat for `--stage stage` after Step 5 is verified. **Never** auto-deploy `--stage prod` from a dev machine — that's `harness-deploy-execute`'s job (via CI).

### 7. Verify

- Worker URL emitted by `alchemy deploy` → health check passes.
- `wrangler d1 migrations apply Db --env stage --remote` succeeds.
- R2 dummy `put` / `get` via `wrangler r2 object` succeeds.
- `bunx alchemy state tree` shows the expected resources.

## Adopting existing Cloudflare resources

```bash
nix develop --command bunx alchemy deploy --stage prod --adopt
```

Or set `adopt: true` per-resource in `alchemy.run.ts` and re-deploy.

## Done

- [ ] `dev/alchemy.run.ts` committed (no secrets inside)
- [ ] `package.json` pins `alchemy` to a specific beta
- [ ] `bunx alchemy plan --stage dev` produces a clean diff
- [ ] D1 / R2 / Worker created in the Cloudflare dashboard
- [ ] `dev/wrangler.jsonc` populated with real D1 ids from `alchemy state`
- [ ] All GitHub Secrets / Variables populated via `scripts/setup-secrets.sh`
- [ ] `DEPLOY_READY=yes` appended to `.my-harness/.config`

## Related

- Secrets registration: `scripts/setup-secrets.sh` + `docs/SETUP.md`
- No-hardcode policy: see `rules/no-hardcoded-secrets.md`
- Execution: `harness-deploy-execute`
- Infrastructure details: `docs/INFRA.md`
