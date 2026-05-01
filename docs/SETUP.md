# セットアップ手順（GitHub Actions Variables / Secrets）

ハーネスを動かすために必要な GitHub の Variables / Secrets を `gh` CLI で対話的に登録する手順。
**すべて値を含めずキー名だけを表に列挙** してあるので、対面で値を入力しながら登録してください。

## Variables（公開可、ビルドタイムに参照）

| 名称 | 用途 | 例 |
|------|------|-----|
| `DEV_URL` | dev 環境のベース URL | `https://dev.example.com` |
| `STAGE_URL` | stage 環境のベース URL（OWASP ZAP の対象） | `https://stage.example.com` |
| `PROD_URL` | 本番 URL | `https://example.com` |
| `STAGE_IPA_PATH` | MobSF にかける iOS ビルドの artifact 内パス | `build/app.ipa` |
| `R2_BACKUP_BUCKET` | DB バックアップ保存先の R2 バケット名 | `harness-prod-backups` |
| `AGE_RECIPIENTS` | バックアップ暗号化用 age 公開鍵（スペース区切り） | `age1xxx age1yyy` |

登録コマンド:

```bash
gh variable set DEV_URL --repo <owner/repo>
gh variable set STAGE_URL --repo <owner/repo>
gh variable set PROD_URL --repo <owner/repo>
gh variable set STAGE_IPA_PATH --repo <owner/repo>
gh variable set R2_BACKUP_BUCKET --repo <owner/repo>
gh variable set AGE_RECIPIENTS --repo <owner/repo>
```

`gh variable set` は対話で値を促すので、安全にコピー&ペースト可能。

## Secrets（暗号化必須、ログ出力されない）

| 名称 | 用途 |
|------|------|
| `ANTHROPIC_API_KEY` | Claude Code Action 用 API キー |
| `RESEND_API_KEY` | パスワードリセット等のメール送信 |
| `EMAIL_FROM_ADDRESS` | 送信元（認証済みドメイン配下） |
| `PROD_DATABASE_URL` | 本番 DB（pg_dump 用） |
| `STAGE_DATABASE_URL` | stage DB（restore 先） |
| `R2_ACCESS_KEY_ID` | Cloudflare R2 アクセスキー |
| `R2_SECRET_ACCESS_KEY` | R2 シークレット |
| `R2_ENDPOINT_URL` | R2 のエンドポイント URL |
| `AGE_SECRET_KEY_STAGE` | stage 復元用 age 秘密鍵 |
| `MOBSF_API_KEY` | MobSF への認証 |
| `CLOUDFLARE_API_TOKEN` | Terraform で Cloudflare 操作する場合 |

登録コマンド:

```bash
gh secret set ANTHROPIC_API_KEY --repo <owner/repo>
gh secret set RESEND_API_KEY --repo <owner/repo>
gh secret set EMAIL_FROM_ADDRESS --repo <owner/repo>
gh secret set PROD_DATABASE_URL --repo <owner/repo>
gh secret set STAGE_DATABASE_URL --repo <owner/repo>
gh secret set R2_ACCESS_KEY_ID --repo <owner/repo>
gh secret set R2_SECRET_ACCESS_KEY --repo <owner/repo>
gh secret set R2_ENDPOINT_URL --repo <owner/repo>
gh secret set AGE_SECRET_KEY_STAGE --repo <owner/repo>
gh secret set MOBSF_API_KEY --repo <owner/repo>
gh secret set CLOUDFLARE_API_TOKEN --repo <owner/repo>
```

## ブランチプロテクション

リポジトリ作成直後に必ず実行する:

```bash
bash .harness/scripts/setup-branch-protection.sh <owner/repo>
```

これで main / stage / dev に対して以下が一括設定される:
- force-push 禁止 (`allow_force_pushes=false`)
- 削除禁止 (`allow_deletions=false`)
- 必須 PR レビュー（main=2 件、stage/dev=1 件）
- 必須 status checks（quality / e2e / security / claude-review）
- 会話解決必須 (`required_conversation_resolution=true`)
- merge コミット保持 (`allow_merge_commit=true`、squash/rebase 禁止)
- マージ後ブランチ自動削除

## auto-merge を有効化

`setup-branch-protection.sh` が `allow_auto_merge=true` を自動で適用するため追加操作は不要。

## Resend ドメイン認証

1. <https://resend.com/domains> でドメイン追加。
2. 表示される DNS レコード（SPF / DKIM / DMARC）を Cloudflare の `cloudflare_record` リソースで Terraform 管理。
3. 認証完了後、`EMAIL_FROM_ADDRESS` をそのドメイン配下のアドレスに設定。

## Cloudflare R2 バックアップバケット

```bash
nix develop --command terraform apply -target=cloudflare_r2_bucket.harness_backup
```

```hcl
resource "cloudflare_r2_bucket" "harness_backup" {
  account_id = var.cloudflare_account_id
  name       = "harness-prod-backups"
  location   = "APAC"
}
```

ライフサイクルルール（90 日経過で削除）は R2 ダッシュボードで設定するか、`cloudflare_r2_lifecycle` リソースを使う。
