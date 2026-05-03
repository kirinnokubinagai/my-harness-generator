---
name: harness-deploy-execute
description: dev → stage → main の段階デプロイを実行する。stage は OWASP ZAP / Playwright / Maestro 必須、main は人間承認 + canary 10% → 100%。「デプロイする」「リリース」「stage に上げる」「本番に出す」等の文脈で発火。
---

# harness-deploy-execute

実装と `harness-deploy-setup` 完了後、各環境への段階リリースを進める skill。

## 前提

- `harness-deploy-setup` 完了済（`infra/` で `terraform apply` 済、`.my-harness/.config` に `DEPLOY_READY=yes`）
- すべての feature が dev にマージ済 / 全 CI green

## デプロイの 3 段階

### A. dev → stage（自動化されているがユーザー承認必須）

```bash
git checkout stage
git fetch origin
gh pr create --base stage --head dev --title "release: dev → stage <date>"
```

`pr-to-stage.yml` が走り:
- quality（biome / vitest / tsc）
- e2e（Playwright + Maestro）
- security（OWASP ZAP + MobSF + 履歴 gitleaks）
- 全 green でも **`approved-for-stage` ラベル必須**（人間承認）

CI 失敗時は `maybe-create-issue.js` が自動で issue（または `docs/task/auto/`）を作成。

ユーザーが承認:
```bash
gh pr review <pr-number> --approve
gh pr edit <pr-number> --add-label approved-for-stage
gh pr merge <pr-number> --auto --merge
```

stage マージ後、自動で stage 環境へデプロイ:
- Cloudflare Pages がブランチ stage を pickup
- D1 stage への migration（`wrangler d1 migrations apply DB --env staging --remote`）
- R2 から本番バックアップを復元（`scheduled-db-backup.yml` の restore-to-stage ジョブ）
- TestFlight ビルドアップロード（USE_IOS=yes のとき）

### B. stage → main（24h 以上 stage で安定後）

stage の最新コミットが **24 時間以上** ステージング環境で安定していることを確認:
- メトリクス（p95 / エラー率 / 認証失敗）異常なし
- ZAP / E2E が緑のまま（再走 OK）

```bash
gh release create vX.Y.Z --draft --generate-notes --target stage
gh pr create --base main --head stage \
  --title "release: stage → main vX.Y.Z" \
  --body-file .github/release-pr-body.md
gh pr edit <pr-number> --add-label approved-for-prod
gh pr merge <pr-number> --auto --merge
```

`pr-to-main.yml` が再度全ゲート（pr-to-stage を再利用）+ `approved-for-prod` ラベル確認。

### C. canary 10% → 100%

main マージ後の本番デプロイは段階的:

```bash
# Cloudflare Pages のトラフィック分割（または Workers の versioned deployment）
nix develop --command pnpm exec wrangler deployments deploy --env production --percent 10
```

10% で 30 分 → メトリクス確認:
```bash
nix develop --command bash .my-harness/scripts/check-canary-health.sh
```

問題なければ:
```bash
nix develop --command pnpm exec wrangler deployments deploy --env production --percent 100
```

GitHub Release を draft → published に:
```bash
gh release edit vX.Y.Z --draft=false
```

## ロールバック

問題発生時は `git revert` ベース（rebase / reset 禁止、`harness-git-discipline` 準拠）:

```bash
git checkout main
git revert -m 1 <merge-sha>     # マージコミットを revert
git push origin main
```

または canary を 100% → 0% に戻して旧バージョンに切替:
```bash
nix develop --command pnpm exec wrangler rollback <previous-deployment-id>
```

## hotfix のときは `harness-new-hotfix` を使う

通常デプロイのフローを飛ばす緊急修正は本 skill ではなく `harness-new-hotfix` を使う（`docs/HOTFIX.md` 参照）。

## チェックリスト

### dev → stage
- [ ] dev のすべての CI が green
- [ ] PR `--base stage --head dev` 作成
- [ ] OWASP ZAP / Playwright / Maestro 緑
- [ ] `approved-for-stage` ラベル付与（人間承認）
- [ ] auto-merge で stage 反映

### stage → main
- [ ] stage 環境で 24h 以上稼働
- [ ] メトリクス異常なし
- [ ] `gh release create --draft`
- [ ] `approved-for-prod` ラベル付与
- [ ] auto-merge で main 反映

### canary
- [ ] 10% で 30 分監視
- [ ] エラー率 / レイテンシ異常なし
- [ ] 100% に昇格
- [ ] `gh release edit --draft=false`

## 関連 skill

- 設定: `harness-deploy-setup`
- hotfix: `harness-new-hotfix`
- Git 規律: `harness-git-discipline`
- secrets: `harness-setup-secrets`
- インフラ詳細: `docs/INFRA.md`
