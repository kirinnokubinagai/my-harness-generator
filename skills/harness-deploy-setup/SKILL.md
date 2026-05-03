---
name: harness-deploy-setup
description: Terraform でデプロイインフラを定義し、Cloudflare（Pages / Workers / R2 / D1 / Tunnel）/ GitHub Actions の必要 secrets / wrangler / fastlane（iOS）等を一括セットアップする。実装フェーズが完了し、いざデプロイする手前で発火。「デプロイ設定」「Terraform で IaC」「Cloudflare 設定」「初回デプロイ準備」等の文脈で発火。
---

# harness-deploy-setup

実装が一段落し、これから dev → stage → main の各環境にデプロイするための **インフラとシークレット** を Terraform 中心で構築する skill。

## 前提

- `/my-harness-init` で `.my-harness/.config` が確定済（`USE_DB`, `USE_EMAIL` 等が読まれる）
- リポジトリが GitHub に push 済（`gh repo view` で確認可能）
- ブランチ保護は `harness-branch-protection` で適用済

## やること（順）

### 1. Terraform プロジェクトを `infra/` に生成

```
<root>/dev/infra/
├── main.tf                  Cloudflare provider 定義 + リソース宣言
├── variables.tf             variable "cloudflare_account_id" 等
├── terraform.tfvars         ローカル用（gitignore）
├── secrets/
│   └── cloudflare.enc.json  SOPS 暗号化（.gitignore + age 公開鍵で保護）
└── README.md
```

### 2. 必要リソースを宣言

`.my-harness/.config` の選択に応じて:

- **USE_WEB=yes** → `cloudflare_pages_project` + `cloudflare_record`（DNS）
- **USE_DB=yes** + `DB_KIND=d1` → `cloudflare_d1_database` × 2（prod / staging）
- バックアップ用 → `cloudflare_r2_bucket`
- USE_EMAIL=yes → SPF / DKIM / DMARC を `cloudflare_record` で（Resend 連携）
- USE_IOS=yes → `fastlane` 設定（`fastlane/Fastfile`、Match 用 git repo）
- USE_ANDROID=yes → Google Play Console サービスアカウント JSON 取扱い

### 3. GitHub Actions vars / secrets を設定（`harness-setup-secrets` を呼ぶ）

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-secrets.sh <owner>/<repo>
```

### 4. Wrangler 設定の最終化

```toml
# wrangler.toml
[[d1_databases]]
binding = "DB"
database_name = "<prod-name>"
database_id = "<terraform output から取得>"

[env.staging]
[[env.staging.d1_databases]]
binding = "DB"
database_name = "<stage-name>"
database_id = "<terraform output から取得>"
```

### 5. terraform apply（dev / stage 環境分）

```bash
cd dev/infra
nix develop --command terraform init
nix develop --command terraform plan -var-file=terraform.tfvars
nix develop --command terraform apply -var-file=terraform.tfvars
```

ステート保存: R2 バックエンドを推奨（terraform `backend "s3"` + R2 互換 endpoint）。

### 6. デプロイ動作確認

- 手動で Pages / Workers にダミーデプロイ → ヘルスチェックが通る
- D1 マイグレーションが `wrangler d1 migrations apply` で適用できる
- R2 にダミーオブジェクトを put / get できる

## 生成サンプル（最小）

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
    # R2 互換: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY を環境変数で
    bucket = "harness-terraform-state"
    key    = "<project>/terraform.tfstate"
    region = "auto"
    endpoints = { s3 = "https://<account>.r2.cloudflarestorage.com" }
  }
}

provider "cloudflare" {
  # CLOUDFLARE_API_TOKEN を環境変数で（ハードコード禁止 → harness-no-hardcoded-secrets）
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

## 完了時に確認すること

- [ ] `infra/main.tf` がコミットされている（terraform.tfvars は gitignore）
- [ ] `terraform plan` がエラー無く通る
- [ ] D1 / R2 / Pages がダッシュボードで作成済
- [ ] GitHub Secrets / Variables が `harness-setup-secrets` で全部入った
- [ ] `wrangler.toml` の database_id が terraform output と一致
- [ ] `.my-harness/.config` の `DEPLOY_READY=yes` を追記

## 関連 skill

- secrets 登録: `harness-setup-secrets`
- ハードコード禁止: `harness-no-hardcoded-secrets`
- 実行: `harness-deploy-execute`
- インフラ詳細: `docs/INFRA.md`
