---
name: harness-deploy-setup
description: Defines deploy infrastructure with Alchemy v2 (Effect.ts) and sets up Cloudflare (Workers / R2 / D1 / KV / DNS / Tunnel), GitHub Actions secrets, wrangler, and fastlane (iOS) in one pass. Generates `dev/alchemy.run.ts` (Effect.gen + yield* per Alchemy v2 syntax) and the corresponding stage configuration. Fires when implementation is complete and the next step is deployment: "deploy setup", "IaC with Alchemy", "Cloudflare setup", "initial deploy prep", or similar.
---

# harness-deploy-setup

The skill for building the **infrastructure and secrets** needed to deploy across the dev → stage → main pipeline, centered on **Alchemy v2 (Effect.ts, TypeScript-native IaC)**, after implementation is complete.

## Why Alchemy v2 (not Terraform / OpenTofu)

- **TypeScript-native** — same language as the rest of the harness; no HCL context switch.
- **Effect.ts based** — composable retries, structured error handling, generator-driven resource declarations (`Effect.gen` + `yield*`).
- **Cloudflare-first** — first-class providers for Workers / D1 / R2 / KV / Queues / Hyperdrive / Tunnel / Zone / DNS / Access / Workers AI. Cloudflare Pages is **not** a target for this harness (use `Cloudflare.Worker` + assets if a static site is needed).
- **State store on Cloudflare** — remote state can live in a Cloudflare Worker + Durable Object (no AWS dependency).
- **Adopt existing resources** — `--adopt` flag pulls existing Cloudflare resources into Alchemy management.

⚠️ Alchemy v2 is `2.0.0-beta.x` (Effect v4 dependency). Expect occasional breaking changes during the beta. Pin the exact version in `package.json` and update intentionally.

## Prerequisites

- `.my-harness/.config` is finalized from `/my-harness-init` (`USE_DB`, `USE_EMAIL`, etc. are set).
- Repository is pushed to GitHub (`gh repo view` confirms).
- Branch protection has been applied via `harness-branch-protection`.
- Bun is installed in the Nix shell (provided by `templates/nix/flake.nix`).

## Steps (in order)

### 1. Install Alchemy v2 in the project

Run inside `<root>/dev`:

```bash
nix develop --command bun add alchemy effect @effect/platform-bun @effect/platform-node
nix develop --command bun add -d @cloudflare/workers-types
```

Pin `alchemy` to a specific beta in `package.json`:

```json
{
  "dependencies": {
    "alchemy": "2.0.0-beta.36"
  }
}
```

### 2. Generate `dev/alchemy.run.ts`

This is the single source of truth for Cloudflare infrastructure. Generate it from the `.my-harness/.config` selections:

```typescript
// dev/alchemy.run.ts
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Effect from "effect/Effect";

export default Alchemy.Stack(
  "harness",                       // stack name (project)
  {
    providers: Cloudflare.providers(),
    state: Cloudflare.state(),     // remote state in Cloudflare DO
  },
  Effect.gen(function* () {
    // Determine stage from CLI flag (--stage dev|stage|prod) or env STAGE
    // Each stage produces an isolated set of Cloudflare resources

    // === D1 (USE_DB=yes && DB_KIND=d1) ===
    const db = yield* Cloudflare.D1Database("Db", {
      name: `harness-${process.env.STAGE ?? "dev"}`,
      // adopt: true,  // uncomment to import an existing D1 by the same name
    });

    // === R2 backup bucket ===
    const backupBucket = yield* Cloudflare.R2Bucket("BackupBucket", {
      name: `harness-${process.env.STAGE ?? "dev"}-backups`,
    });

    // === KV (optional, if used) ===
    // const kv = yield* Cloudflare.KVNamespace("Kv", { title: "harness-kv" });

    // === Worker (USE_WEB=yes typically renders into a Worker + Assets) ===
    const worker = yield* Cloudflare.Worker("Api", {
      main: "./src/worker.ts",
      url: true,
      bindings: {
        Db: db,
        BackupBucket: backupBucket,
        // Kv: kv,
      },
    });

    // === DNS records (USE_EMAIL=yes adds SPF / DKIM / DMARC) ===
    // const zone = yield* Cloudflare.Zone("ApexZone", { name: "example.com" });
    // yield* Cloudflare.DnsRecords("EmailDns", {
    //   zone,
    //   records: [
    //     { type: "TXT", name: "@",         content: "v=spf1 include:_spf.resend.com ~all" },
    //     { type: "TXT", name: "_dmarc",    content: "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com" },
    //     { type: "TXT", name: "resend._domainkey", content: "<dkim public key from Resend>" },
    //   ],
    // });

    return {
      worker_url: worker.url,
      d1_id:      db.id,
      bucket:     backupBucket.name,
    };
  }),
);
```

Save to `<root>/dev/alchemy.run.ts`. **Do not** commit secrets to this file — use environment variables (Step 4).

### 3. Set GitHub Actions vars / secrets

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-secrets.sh <owner>/<repo>
```

Required secrets for Alchemy v2 + Cloudflare:

- `CLOUDFLARE_API_TOKEN` — API token with Workers / D1 / R2 / KV permissions
- `CLOUDFLARE_ACCOUNT_ID` — your Cloudflare account ID

These are read by Alchemy at deploy time. **Do not put them in `alchemy.run.ts`.**

### 4. Configure local Alchemy authentication (developer machines)

For local dry-runs and the first deploy from a developer machine:

```bash
nix develop --command bunx alchemy login --configure
# Pick "Cloudflare", paste API token + account ID, save under profile name `dev` (default)
# For prod: bunx alchemy login --profile prod --configure
```

Profiles are stored at `~/.alchemy/profiles.json` (plain JSON; do not commit). For SOPS-encrypted credentials in the repo, decrypt before invoking Alchemy:

```bash
nix develop --command sh -c '
  export CLOUDFLARE_API_TOKEN=$(sops -d secrets/cloudflare.enc.json | jq -r .api_token)
  export CLOUDFLARE_ACCOUNT_ID=$(sops -d secrets/cloudflare.enc.json | jq -r .account_id)
  bunx alchemy deploy --stage dev
'
```

### 5. wrangler binding sync (D1 migrations only)

Alchemy v2's `alchemy dev` uses an internal workerd, but `wrangler d1 migrations apply` is still useful for D1 schema changes. Generate a minimal `wrangler.jsonc` by hand (Alchemy v2 does **not** auto-generate it):

```jsonc
// dev/wrangler.jsonc
{
  "name": "harness",
  "main": "src/worker.ts",
  "compatibility_date": "2025-05-01",
  "d1_databases": [
    { "binding": "Db", "database_name": "harness-dev",   "database_id": "<filled by alchemy state get harness dev Db>" }
  ],
  "env": {
    "stage": {
      "d1_databases": [
        { "binding": "Db", "database_name": "harness-stage", "database_id": "<filled by alchemy state get harness stage Db>" }
      ]
    },
    "prod": {
      "d1_databases": [
        { "binding": "Db", "database_name": "harness-prod",  "database_id": "<filled by alchemy state get harness prod Db>" }
      ]
    }
  }
}
```

Pull the actual D1 ids from Alchemy state after the first deploy:

```bash
nix develop --command bunx alchemy state get harness dev Db | jq -r .id
```

### 6. First deploy (creates resources in Cloudflare)

Dry-run first to see the plan:

```bash
nix develop --command bunx alchemy plan --stage dev
```

Then deploy:

```bash
nix develop --command bunx alchemy deploy --stage dev --yes
```

Repeat for `--stage stage` after Step 5 is verified. **Do not** auto-deploy `--stage prod` from the dev machine; that goes through CI (`harness-deploy-execute`).

### 7. Verify deployment works

- Hit the Worker URL emitted by `alchemy deploy` — health check passes
- `wrangler d1 migrations apply Db --env stage --remote` succeeds
- R2 dummy `put` / `get` succeeds via `wrangler r2 object`
- `bunx alchemy state tree` shows the expected resources

## Adopting existing Cloudflare resources

If the Cloudflare account already has a `harness-prod` D1 or `harness-prod-backups` R2 from manual / Terraform provisioning, take ownership without recreation:

```bash
nix develop --command bunx alchemy deploy --stage prod --adopt
```

Or per-resource by adding `adopt: true` in `alchemy.run.ts` and re-running deploy.

## Cloudflare Pages

**Out of scope for this harness.** If a static site is needed, render it via `Cloudflare.Worker` + assets (Workers Static Assets), not Pages.

## Completion checklist

- [ ] `dev/alchemy.run.ts` committed (no secrets inside)
- [ ] `package.json` pins `alchemy` to a specific beta
- [ ] `bunx alchemy plan --stage dev` produces a clean diff
- [ ] D1 / R2 / Worker created in the Cloudflare dashboard
- [ ] `dev/wrangler.jsonc` populated with real D1 ids from `alchemy state`
- [ ] All GitHub Secrets / Variables populated via `harness-setup-secrets`
- [ ] `DEPLOY_READY=yes` appended to `.my-harness/.config`

## Related skills

- Secrets registration: `harness-setup-secrets`
- No-hardcode policy: see `rules/no-hardcoded-secrets.md`
- Execution: `harness-deploy-execute`
- Infrastructure details: `docs/INFRA.md`
