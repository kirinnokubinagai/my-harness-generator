---
name: harness-new-hotfix
description: 本番障害の緊急修正用 worktree を main 起点で作成する。`new-hotfix.sh` をラップ。「hotfix」「本番障害」「緊急修正」「main から修正」等の文脈で発火。
---

# harness-new-hotfix

緊急度高の本番障害修正のために、main 起点の `hotfix/<issue>-<slug>` ブランチで worktree を立ち上げる。

## 通常 feature との違い

| 項目 | 通常 feature | hotfix |
|------|-------------|--------|
| 起点ブランチ | dev | **main** |
| PR 先 | dev | **main** |
| stage 経由 | 必須 | スキップ可 |
| OWASP ZAP / E2E | pre-merge | post-merge 即時 |
| SLA | 通常 | **24 時間以内** |
| 親 issue | 必須 | post-mortem として事後作成 |

## 呼び出し

```bash
cd <root>
bash .my-harness/scripts/new-hotfix.sh <issue-number> <slug>
# → lanes/hotfix-<issue>-<slug>/ に main 起点 worktree
```

## 完了後のフロー（厳守）

1. 修正 + 最小テスト（regression test 必須）
2. `git push` → `gh pr create --base main`
3. **緊急承認** + 最小ゲート CI（biome / vitest / tsc / trivy）通過 → マージ
4. **post-merge で OWASP ZAP / E2E 即時実行**（不合格時は即ロールバック）
5. **逆流マージ（必ず `git merge --no-ff`、rebase / reset 禁止）**:
   ```bash
   git checkout stage && git fetch origin
   git merge --no-ff origin/main -m "merge: hotfix back-merge main → stage"
   git push origin stage
   git checkout dev
   git merge --no-ff origin/stage -m "merge: hotfix back-merge stage → dev"
   git push origin dev
   ```
6. **24h 以内に post-mortem 親 issue 起票**、再発防止子 issue で展開

## 禁止事項

- main に直接 push
- `git rebase` / `git reset --hard` / `git push --force`
- 逆流をスキップ（次回 release で衝突する）

## 関連

- 通常開発は `harness-new-feature`
- コンフリクト解消は `harness-resolve-conflict`
- Git 規律全般は `harness-git-discipline`
