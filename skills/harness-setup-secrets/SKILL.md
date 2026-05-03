---
name: harness-setup-secrets
description: GitHub の Secrets / Variables を対話的に登録する。`setup-secrets.sh` をラップ。`.my-harness/.config` の選択（USE_CODEX / USE_EMAIL / USE_DB 等）に応じて必要な secrets だけ訊く。「GitHub secrets を設定」「初回セットアップの secrets」等の文脈で発火。
---

# harness-setup-secrets

ハーネス対応プロジェクトに必要な GitHub Secrets / Variables を `gh` CLI で対話登録する。bootstrap 完了後の **初回 1 回** だけ実行する想定。

## 必須前提

- `gh auth status` が OK（GitHub にログイン済み）
- リポジトリ作成済み（`gh repo create` 後）
- `<root>/.my-harness/.config` が存在（bootstrap 済み）

## 呼び出し

```bash
cd <root>
bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>
```

## 対話プロンプト

`.my-harness/.config` の選択に応じて必要分だけプロンプト:

### 共通（全プロジェクト）
- `DEV_URL` / `STAGE_URL` / `PROD_URL`（vars）

### USE_CLAUDE_ACTION=yes のとき
- `CLAUDE_CODE_OAUTH_TOKEN`（OAuth）または `ANTHROPIC_API_KEY`（API key）

### USE_EMAIL=yes のとき
- `RESEND_API_KEY` / `EMAIL_FROM_ADDRESS`

### USE_DB=yes（DB_KIND=d1）のとき
- `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_D1_DATABASE_ID`
- `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_ENDPOINT_URL`
- `R2_BACKUP_BUCKET`（var） / `AGE_RECIPIENTS`（var）
- `AGE_SECRET_KEY_STAGE`

### モバイル（USE_IOS / USE_ANDROID=yes）のとき
- `MOBSF_API_KEY`

### USE_IOS=yes のとき
- `APP_STORE_CONNECT_API_KEY_ID` / `_ISSUER_ID` / `_KEY_BASE64`
- `MATCH_PASSWORD` / `MATCH_GIT_BASIC_AUTHORIZATION`

## 動作

各 secret/var に対して `gh secret set` / `gh variable set` を起動 → 対話で値入力（標準入力やペースト）。空入力でその secret はスキップ。

## 機密管理ベスプラ

- 値はターミナル履歴に残らないよう、対話で直接入力
- 共有が必要な値は **SOPS + age** で暗号化したファイル（`secrets/*.enc.json`）に書き、CI で復号する流れも併用可
- 詳細は `<root>/.my-harness/docs/SETUP.md` 参照

## 関連

- branch protection: `harness-branch-protection`
- ハードコード禁止: `harness-no-hardcoded-secrets`
