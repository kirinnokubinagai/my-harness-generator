# インフラ規約（質問16・補足）

## 原則

- **完全 IaC**: 手動コンソール変更を禁止。Terraform を Nix flake で固定。
- **Nix pure**: 開発環境は `nix develop` 一発で再現。Docker も Nix で固める（`dockerTools.buildImage`）。
- **不変インフラ**: 変更は再ビルド + 再デプロイで反映、SSH での直接修正は禁止。

## 推奨スタック

| レイヤー | 推奨 | 代替 |
|----------|------|------|
| クラウド | AWS / GCP / Cloudflare | Fly.io（小規模） |
| コンテナ実行 | ECS Fargate / Cloud Run | Kubernetes |
| データベース | RDS PostgreSQL / Cloud SQL | Supabase |
| キャッシュ | ElastiCache Redis | Upstash |
| オブジェクト | S3 / GCS / R2 | - |
| CDN / WAF | Cloudflare | AWS CloudFront + WAF |
| シークレット | SOPS + age（リポ内）/ AWS Secrets Manager（本番） | - |
| 監視 | Datadog / CloudWatch + Grafana | Sentry |
| CI/CD | GitHub Actions | - |

## デプロイトリガー

| 環境 | 起点 | 方法 |
|------|------|------|
| development | dev push | 自動（feature プレビュー） |
| staging | stage への merge | 自動 + 人間承認 |
| production | main への merge | 自動 + 人間承認 + canary 10% → 100% |

## Cloudflare を使う場合（Terraform 対応）

Cloudflare は **公式 Terraform プロバイダ `cloudflare/cloudflare`（v4 系）** が成熟しており、
以下のリソースをすべて IaC で管理できる。

| リソース | プロバイダ側の対応 |
|----------|------------------|
| DNS レコード | `cloudflare_record` |
| Pages プロジェクト | `cloudflare_pages_project` / `cloudflare_pages_domain` |
| Workers / Workers Routes | `cloudflare_workers_script` / `cloudflare_workers_route` |
| R2 バケット | `cloudflare_r2_bucket` |
| KV / D1 / Queues | `cloudflare_workers_kv_namespace` / `cloudflare_d1_database` / `cloudflare_queue` |
| Cloudflare Tunnel（旧 Argo Tunnel） | `cloudflare_zero_trust_tunnel_cloudflared` |
| Access（ZTNA） | `cloudflare_access_application` / `cloudflare_access_policy` |
| WAF カスタムルール | `cloudflare_ruleset`（phase=`http_request_firewall_custom`） |
| Page Rules / Bulk Redirects | `cloudflare_ruleset`（phase=`http_request_dynamic_redirect`） |
| Turnstile | `cloudflare_turnstile_widget` |

### Nix flake から Terraform を pure 実行

`flake.nix` の `buildInputs` に既に `terraform` を含めているため、

```bash
nix develop --command terraform init
nix develop --command terraform plan
```

がそのまま動く。Cloudflare API トークンは **SOPS で暗号化したファイル** から復号して環境変数に注入する想定:

```bash
nix develop --command sh -c '
  export CLOUDFLARE_API_TOKEN=$(sops -d secrets/cloudflare.enc.json | jq -r .api_token)
  terraform apply
'
```

### 最小サンプル（DNS + Pages）

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
  # CLOUDFLARE_API_TOKEN は環境変数で渡す（直書き禁止）
}

variable "zone_id" { type = string }
variable "account_id" { type = string }

resource "cloudflare_record" "apex" {
  zone_id = var.zone_id
  name    = "@"
  type    = "A"
  value   = "192.0.2.1"
  proxied = true
  comment = "本番アペックスを Cloudflare 経由で公開する設定"
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

注意:
- `value` 等のリテラル値はサンプル用。本番値は `terraform.tfvars`（`.gitignore` 済み）または SOPS で管理する。
- ステート保存は `cloudflare_r2_bucket` + Terraform の `s3` バックエンド互換で R2 を使うと AWS 不要で完結する。

## D1 バックアップ運用（質問6 + 11 への回答）

| ステップ | コマンド |
|---------|----------|
| 本番 SQL エクスポート | `wrangler d1 export DB --remote --output prod.sql` |
| age で暗号化 | `age -r <pubkey> -o prod.sql.age prod.sql` |
| R2 へアップロード | `aws s3 cp prod.sql.age s3://<bucket>/backups/ --endpoint-url <r2>` |
| stage を初期化 | `wrangler d1 execute DB --env staging --command "DROP TABLE ..."` |
| stage に復元 | `wrangler d1 execute DB --env staging --file prod.sql` |
| 追加マイグレ再適用 | `wrangler d1 migrations apply DB --env staging --remote` |

すべて `scheduled-db-backup.yml` で 3 日に 1 回自動。失敗時は GitHub issue を `priority/p0` で起票。

## Android SDK の扱い（質問12 補足）

Nix flake には JDK21 と adb 系の `android-tools` だけ含めている。
Android SDK の `platform-tools` / `build-tools` / Emulator は Google 配布のため Nix 完全 pure 化が難しい。
そのため Android を扱う場合のみ、追加で:

```bash
# 初回だけ手動
brew install --cask android-commandlinetools  # または公式 zip
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
export ANDROID_HOME=$HOME/Library/Android/sdk
```

CI（GitHub Actions）では `actions/setup-java@v4` + `android-actions/setup-android@v3` で再現可能。

## ロールバック

- 各環境は **直前の immutable イメージタグ** を即座に再デプロイできるようにする。
- DB マイグレーションは **forward-only**、破壊的変更は 2 段階で実施（add → backfill → switch → drop）。
