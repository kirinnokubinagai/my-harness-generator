# Infrastructure Policy

## Principles

- **Fully IaC**: manual console changes are prohibited. Cloudflare infrastructure is declared in `dev/alchemy.run.ts` and managed by **Alchemy v2 (Effect.ts)** — pinned via `package.json`. Bun (the recommended Alchemy v2 runtime) is pinned via Nix flake.
- **Nix pure**: the development environment is fully reproducible with a single `nix develop`. Docker images are also built with Nix (`dockerTools.buildImage`).
- **Immutable infrastructure**: changes are applied via rebuild + redeploy; direct SSH modifications are prohibited.

## Recommended Stack

| Layer | Recommended | Alternative |
|-------|-------------|-------------|
| Cloud | AWS / GCP / Cloudflare | Fly.io (small scale) |
| Container runtime | ECS Fargate / Cloud Run | Kubernetes |
| Database | RDS PostgreSQL / Cloud SQL / Cloudflare D1 | Supabase |
| Cache | ElastiCache Redis | Upstash |
| Object storage | S3 / GCS / R2 | - |
| CDN / WAF | Cloudflare | AWS CloudFront + WAF |
| Secrets | SOPS + age (in repo) / AWS Secrets Manager (prod) / GitHub Secrets (CI) | - |
| Cloudflare IaC | **Alchemy v2** (TypeScript / Effect.ts) | wrangler-only (no IaC) |
| Monitoring | Datadog / CloudWatch + Grafana | Sentry |
| CI/CD | GitHub Actions | - |

## Deploy Triggers

| Environment | Trigger | Method |
|-------------|---------|--------|
| development | dev push | Automatic (feature preview) |
| staging | merge to stage | Automatic + human approval |
| production | merge to main | Automatic + human approval + canary 10% → 100% |

## Cloudflare IaC — Alchemy v2

This harness uses **Alchemy v2** (`alchemy@2.0.0-beta.x`, Effect.ts based) for all Cloudflare infrastructure-as-code. The single source of truth is `dev/alchemy.run.ts` (Effect.gen + `yield*` resource declarations).

**Why not Terraform / OpenTofu**: Alchemy v2 lets us declare Cloudflare infra in the same language as the application (TypeScript), keeps state in a Cloudflare Worker + Durable Object (no AWS dependency), supports `--adopt` for taking over existing resources, and integrates Effect.ts's structured concurrency / retries. Drift detection at Terraform's level is not yet present and the `2.0.0-beta.x` series may introduce breaking changes — pin the version and update intentionally.

**Cloudflare Pages is intentionally out of scope** for this harness. If a static site is needed, render it via `Cloudflare.Worker` + Workers Static Assets, not Pages.

### Resource coverage in Alchemy v2 (`alchemy/Cloudflare`)

| Resource | Alchemy v2 import |
|----------|------------------|
| Workers (script + bindings) | `Cloudflare.Worker` |
| Durable Objects | `Cloudflare.DurableObjectNamespace` |
| Workflows | `Cloudflare.Workflow` |
| D1 databases | `Cloudflare.D1Database` (+ `D1Migrations`, `D1Import`, `D1Export`) |
| R2 buckets | `Cloudflare.R2Bucket` |
| KV namespaces | `Cloudflare.KVNamespace` |
| Queues | `Cloudflare.Queue` / `Cloudflare.QueueConsumer` |
| Hyperdrive | `Cloudflare.Hyperdrive` |
| DNS records | `Cloudflare.DnsRecords` |
| Zone | `Cloudflare.Zone` |
| Cloudflare Tunnel | `Cloudflare.Tunnel` |
| Access (ZTNA) | `Cloudflare.AccessApplication` / `AccessPolicy` / etc. |
| AI Gateway | `Cloudflare.AiGateway` |
| Images | `Cloudflare.Images` |
| Secrets Store | `Cloudflare.SecretsStore` / `Secret` |
| API tokens (programmatic) | `Cloudflare.AccountApiToken` |

### Running Alchemy v2 purely via Nix flake

`bun` is pinned in `templates/nix/flake.nix`. From inside `dev/`:

```bash
nix develop --command bunx alchemy plan   --stage dev
nix develop --command bunx alchemy deploy --stage dev --yes
nix develop --command bunx alchemy state  tree
nix develop --command bunx alchemy destroy --stage dev   # tear down a stage
```

`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` must be in the environment. Decrypt from the SOPS-encrypted file when running locally:

```bash
nix develop --command sh -c '
  export CLOUDFLARE_API_TOKEN=$(sops -d secrets/cloudflare.enc.json | jq -r .api_token)
  export CLOUDFLARE_ACCOUNT_ID=$(sops -d secrets/cloudflare.enc.json | jq -r .account_id)
  bunx alchemy deploy --stage dev --yes
'
```

In CI (GitHub Actions) the same env vars come from `gh secret`s — see `.github/workflows/deploy.yml`.

### Minimal sample (`dev/alchemy.run.ts`)

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
    const stage = process.env.STAGE ?? "dev";

    // === D1 (DB_KIND=d1) ===
    const db = yield* Cloudflare.D1Database("Db", {
      name: `harness-${stage}`,
    });

    // === R2 backup bucket ===
    const backupBucket = yield* Cloudflare.R2Bucket("BackupBucket", {
      name: `harness-${stage}-backups`,
      location: "APAC",
    });

    // === Worker (binds D1 + R2) ===
    const worker = yield* Cloudflare.Worker("Api", {
      main: "./src/worker.ts",
      url: true,
      bindings: {
        Db: db,
        BackupBucket: backupBucket,
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

Notes:
- Literal values are sample only. Real values come from `process.env` / SOPS-decrypted env vars at deploy time. No hardcoding (see `rules/no-hardcoded-secrets.md`).
- State store: `Cloudflare.state()` puts Alchemy state in a Cloudflare Worker + Durable Object. No AWS dependency. Manual repair via `bunx alchemy cloudflare ...`.
- `--adopt`: pass at deploy time (`bunx alchemy deploy --stage prod --adopt`) to take over existing Cloudflare resources without recreation.

## D1 Backup Operations

| Step | Command |
|------|---------|
| Export production SQL | `wrangler d1 export DB --remote --output prod.sql` |
| Encrypt with age | `age -r <pubkey> -o prod.sql.age prod.sql` |
| Upload to R2 | `aws s3 cp prod.sql.age s3://<bucket>/backups/ --endpoint-url <r2>` |
| Reset stage | `wrangler d1 execute DB --env staging --command "DROP TABLE ..."` |
| Restore to stage | `wrangler d1 execute DB --env staging --file prod.sql` |
| Re-apply additional migrations | `wrangler d1 migrations apply DB --env staging --remote` |

The R2 bucket and D1 databases used here are themselves provisioned by `dev/alchemy.run.ts` (see sample above). Operate the actual backup schedule from your own GitHub Actions workflow (the plugin no longer ships a template for this).

## Handling the Android SDK

The Nix flake includes only JDK21 and `android-tools` (adb). The Android SDK's `platform-tools` / `build-tools` / Emulator are distributed by Google, making full Nix purity difficult.
When working with Android, additionally run once manually:

```bash
# First time only
brew install --cask android-commandlinetools  # or download the official zip
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
export ANDROID_HOME=$HOME/Library/Android/sdk
```

In CI (GitHub Actions), reproducibility is achieved with `actions/setup-java@v4` + `android-actions/setup-android@v3`.

## Rollback

- Each environment must be able to immediately redeploy **the previous immutable image tag**.
- DB migrations are **forward-only**; destructive changes are applied in two phases (add → backfill → switch → drop).
- Cloudflare Worker rollback: `wrangler rollback <previous-deployment-id>` (Alchemy v2 does not yet expose a first-class rollback command; use wrangler for emergency rollback of the Worker, then `bunx alchemy deploy --adopt` to re-sync state).
