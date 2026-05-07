# Infrastructure Policy

## Principles

- **Fully IaC**: manual console changes are prohibited. Terraform is pinned via Nix flake.
- **Nix pure**: the development environment is fully reproducible with a single `nix develop`. Docker images are also built with Nix (`dockerTools.buildImage`).
- **Immutable infrastructure**: changes are applied via rebuild + redeploy; direct SSH modifications are prohibited.

## Recommended Stack

| Layer | Recommended | Alternative |
|-------|-------------|-------------|
| Cloud | AWS / GCP / Cloudflare | Fly.io (small scale) |
| Container runtime | ECS Fargate / Cloud Run | Kubernetes |
| Database | RDS PostgreSQL / Cloud SQL | Supabase |
| Cache | ElastiCache Redis | Upstash |
| Object storage | S3 / GCS / R2 | - |
| CDN / WAF | Cloudflare | AWS CloudFront + WAF |
| Secrets | SOPS + age (in repo) / AWS Secrets Manager (prod) | - |
| Monitoring | Datadog / CloudWatch + Grafana | Sentry |
| CI/CD | GitHub Actions | - |

## Deploy Triggers

| Environment | Trigger | Method |
|-------------|---------|--------|
| development | dev push | Automatic (feature preview) |
| staging | merge to stage | Automatic + human approval |
| production | merge to main | Automatic + human approval + canary 10% → 100% |

## Using Cloudflare (Terraform-managed)

The official Terraform provider `cloudflare/cloudflare` (v4.x) is mature and supports full IaC management for the following resources:

| Resource | Provider support |
|----------|-----------------|
| DNS records | `cloudflare_record` |
| Pages projects | `cloudflare_pages_project` / `cloudflare_pages_domain` |
| Workers / Workers Routes | `cloudflare_workers_script` / `cloudflare_workers_route` |
| R2 buckets | `cloudflare_r2_bucket` |
| KV / D1 / Queues | `cloudflare_workers_kv_namespace` / `cloudflare_d1_database` / `cloudflare_queue` |
| Cloudflare Tunnel (formerly Argo Tunnel) | `cloudflare_zero_trust_tunnel_cloudflared` |
| Access (ZTNA) | `cloudflare_access_application` / `cloudflare_access_policy` |
| WAF custom rules | `cloudflare_ruleset` (phase=`http_request_firewall_custom`) |
| Page Rules / Bulk Redirects | `cloudflare_ruleset` (phase=`http_request_dynamic_redirect`) |
| Turnstile | `cloudflare_turnstile_widget` |

### Running Terraform Purely via Nix Flake

Since `terraform` is already included in `flake.nix`'s `buildInputs`:

```bash
nix develop --command terraform init
nix develop --command terraform plan
```

run as-is. The Cloudflare API token is assumed to be decrypted from a **SOPS-encrypted file** and injected as an environment variable:

```bash
nix develop --command sh -c '
  export CLOUDFLARE_API_TOKEN=$(sops -d secrets/cloudflare.enc.json | jq -r .api_token)
  terraform apply
'
```

### Minimal Sample (DNS + Pages)

```hcl
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
  }
}

provider "cloudflare" {
  # CLOUDFLARE_API_TOKEN is passed via environment variable (hardcoding prohibited)
}

variable "zone_id" { type = string }
variable "account_id" { type = string }

resource "cloudflare_record" "apex" {
  zone_id = var.zone_id
  name    = "@"
  type    = "A"
  value   = "192.0.2.1"
  proxied = true
  comment = "Expose the production apex through Cloudflare"
}

resource "cloudflare_pages_project" "web" {
  account_id        = var.account_id
  name              = "harness-web"
  production_branch = "main"

  build_config {
    build_command   = "nix develop --command pnpm build"
    destination_dir = "dist"
  }

  source {
    type = "github"
    config {
      owner             = "your-org"
      repo_name         = "your-repo"
      production_branch = "main"
      pr_comments_enabled = true
    }
  }
}
```

Notes:
- Literal values such as `value` are for sample purposes only. Production values are managed via `terraform.tfvars` (in `.gitignore`) or SOPS.
- For state storage, using a `cloudflare_r2_bucket` with Terraform's `s3` backend-compatible R2 eliminates the need for AWS.

## D1 Backup Operations

| Step | Command |
|------|---------|
| Export production SQL | `wrangler d1 export DB --remote --output prod.sql` |
| Encrypt with age | `age -r <pubkey> -o prod.sql.age prod.sql` |
| Upload to R2 | `aws s3 cp prod.sql.age s3://<bucket>/backups/ --endpoint-url <r2>` |
| Reset stage | `wrangler d1 execute DB --env staging --command "DROP TABLE ..."` |
| Restore to stage | `wrangler d1 execute DB --env staging --file prod.sql` |
| Re-apply additional migrations | `wrangler d1 migrations apply DB --env staging --remote` |

All steps run automatically every 3 days via `scheduled-db-backup.yml`. On failure, a GitHub issue is created with the `priority/p0` label.

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
