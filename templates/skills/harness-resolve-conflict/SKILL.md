---
name: harness-resolve-conflict
description: コンフリクト解消を **マージコミットのみ** で行う。`resolve-conflict.sh` をラップ。`git rebase` / `git reset` / `git push --force` を絶対禁止。「コンフリクト」「merge conflict」「rebase 代替」等の文脈で発火。
---

# harness-resolve-conflict

ハーネス配下のすべてのコンフリクト解消は **マージコミットのみ**。`git rebase` / `git reset` / `git push --force` 全部禁止（`harness-git-discipline` に準拠）。

## 呼び出し

```bash
bash <root>/.my-harness/scripts/resolve-conflict.sh <feature-worktree> [base=dev]
```

例:
```bash
bash <root>/.my-harness/scripts/resolve-conflict.sh lanes/feat-42-user-login dev
```

スクリプトは:
1. `git fetch origin <base>` で最新を取得
2. `git merge --no-ff origin/<base>` で取り込み（rebase でない）
3. コンフリクトマーカーが残ったら **engineer が手で両方の意図を保持して解消**
4. 解消後 `git add -A && git commit`
5. `git push origin <branch>`（`--force` 系一切禁止）

## なぜ rebase 禁止か

- 履歴改変は他者の作業を破壊する
- マージコミットは「いつ・誰が・何を」取り込んだかの監査証跡
- 並列 4 レーンで history が壊れない保証

## 解消後の検証

```bash
nix develop --command pnpm exec biome check .
nix develop --command pnpm exec tsc --noEmit
nix develop --command pnpm exec vitest run
```

すべて緑になってから push する。

## hotfix 後の逆流時も同じ

main → stage → dev の逆流マージも `git merge --no-ff` のみ。`harness-new-hotfix` 参照。

## 関連

- Git 規律全般: `harness-git-discipline`
- dev 取込（コンフリクト無いとき）: `harness-sync-features`
