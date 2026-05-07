---
name: harness-deploy-setup
description: Defines deploy infrastructure with Terraform and sets up Cloudflare (Pages / Workers / R2 / D1 / Tunnel), GitHub Actions secrets, wrangler, and fastlane (iOS) in one pass. Fires when implementation is complete and the next step is deployment: "deploy setup", "IaC with Terraform", "Cloudflare setup", "initial deploy prep", or similar.
---

# harness-deploy-setup

The skill for building the **infrastructure and secrets** needed to deploy across the dev → stage → main pipeline, centered on Terraform, after implementation is complete.

## Prerequisites

- `.my-harness/.config` is finalized from `/my-harness-init` (`USE_DB`, `USE_EMAIL`, etc. are set)
- Repository is pushed to GitHub (verify with `gh repo view`)
- Branch protection has been applied via `harness-branch-protection`

## Steps (in order)

### 1. Generate a Terraform project in `infra/`

```
<root>/dev/infra/
├── main.tf                  Cloudflare provider definition + resource declarations
├── variables.tf             variable "cloudflare_account_id", etc.
├── terraform.tfvars         Local values (gitignored)
├── secrets/
│   └── cloudflare.enc.json  SOPS-encrypted (.gitignore + age public key protection)
└── README.md
```

### 2. Declare required resources

Based on the selections in `.my-harness/.config`:

- **USE_WEB=yes** → `cloudflare_pages_project` + `cloudflare_record` (DNS)
- **USE_DB=yes** + `DB_KIND=d1` → `cloudflare_d1_database` × 2 (prod / staging)
- Backup storage → `cloudflare_r2_bucket`
- USE_EMAIL=yes → SPF / DKIM / DMARC via `cloudflare_record` (Resend integration)
- USE_IOS=yes → `fastlane` config (`fastlane/Fastfile`, Match git repo)
- USE_ANDROID=yes → Google Play Console service account JSON handling

### 3. Set GitHub Actions vars / secrets (calls `harness-setup-secrets`)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-secrets.sh <owner>/<repo>
```

### 4. Finalize wrangler configuration

```toml
# wrangler.toml
[[d1_databases]]
binding = "DB"
database_name = "<prod-name>"
database_id = "<retrieved from terraform output>"

[env.staging]
[[env.staging.d1_databases]]
binding = "DB"
database_name = "<stage-name>"
database_id = "<retrieved from terraform output>"
```

### 5. terraform apply (for dev / stage environments)

```bash
cd dev/infra
nix develop --command terraform init
nix develop --command terraform plan -var-file=terraform.tfvars
nix develop --command terraform apply -var-file=terraform.tfvars
```

State storage: R2 backend is recommended (terraform `backend "s3"` + R2-compatible endpoint).

### 6. Verify deployment works

- Manually deploy a dummy build to Pages / Workers → health check passes
- Confirm D1 migrations apply with `wrangler d1 migrations apply`
- Confirm R2 dummy object put / get succeeds

## Minimal generated example

```hcl
# infra/main.tf
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.17"
    }
  }
  backend "s3" {
    # R2-compatible: use AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY as env vars
    bucket = "harness-terraform-state"
    key    = "<project>/terraform.tfstate"
    region = "auto"
    endpoints = { s3 = "https://<account>.r2.cloudflarestorage.com" }
  }
}

provider "cloudflare" {
  # Pass CLOUDFLARE_API_TOKEN via environment variable (no hardcoding — see harness-no-hardcoded-secrets)
}

resource "cloudflare_d1_database" "prod" {
  account_id = var.cloudflare_account_id
  name       = "${var.project_name}-prod"
  primary_location_hint = "apac"
}

resource "cloudflare_d1_database" "staging" {
  account_id = var.cloudflare_account_id
  name       = "${var.project_name}-staging"
}

resource "cloudflare_r2_bucket" "backup" {
  account_id = var.cloudflare_account_id
  name       = "${var.project_name}-backups"
}

output "d1_prod_id" { value = cloudflare_d1_database.prod.id }
output "d1_staging_id" { value = cloudflare_d1_database.staging.id }
```

## Completion checklist

- [ ] `infra/main.tf` committed (terraform.tfvars gitignored)
- [ ] `terraform plan` passes without errors
- [ ] D1 / R2 / Pages created in the Cloudflare dashboard
- [ ] All GitHub Secrets / Variables populated via `harness-setup-secrets`
- [ ] `wrangler.toml` `database_id` matches terraform output
- [ ] `DEPLOY_READY=yes` appended to `.my-harness/.config`

## Related skills

- Secrets registration: `harness-setup-secrets`
- No-hardcode policy: `harness-no-hardcoded-secrets`
- Execution: `harness-deploy-execute`
- Infrastructure details: `docs/INFRA.md`
