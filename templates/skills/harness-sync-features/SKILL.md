---
name: harness-sync-features
description: 全 feature worktree に dev の最新コミットを取り込む（hotfix 逆流後の同期、定期同期）。`sync-features-with-dev.sh` をラップ。「dev を取り込む」「sync」「back-merge」等の文脈で発火。
---

# harness-sync-features

`<root>/lanes/feat-*` 配下の **全 feature worktree** に対し、`origin/dev` を `git merge --no-ff` で取り込む。hotfix 逆流後や定期メンテで実行。

## 呼び出し

```bash
cd <root>
bash .my-harness/scripts/sync-features-with-dev.sh
```

## 動作

1. `git fetch origin dev`
2. `lanes/feat-*` を順に走査
3. 各 worktree で `git merge --no-ff origin/dev -m "merge: sync with origin/dev (no rebase)"`
4. 衝突があれば warning で報告（自動解消はしない、engineer が `harness-resolve-conflict` で解く）

## 使うタイミング

- hotfix が main にマージされ、main → stage → dev に逆流された **直後**（dev に新コミットが入ったので）
- 長期作業中の feature ブランチが dev から離れすぎたとき（週 1 程度）
- リリース（dev → stage）の前

## 衝突発生時の手順

スクリプトは衝突時 exit code 2 を返す:
```bash
bash .my-harness/scripts/sync-features-with-dev.sh
if [ $? -eq 2 ]; then
  echo "衝突したレーンがある。各レーンで harness-resolve-conflict を使って解消"
fi
```

衝突したレーンに移動 → `harness-resolve-conflict` skill を使う。

## 関連

- コンフリクト解消: `harness-resolve-conflict`
- hotfix back-merge: `harness-new-hotfix`
- Git 規律: `harness-git-discipline`
