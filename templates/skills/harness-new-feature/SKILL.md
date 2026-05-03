---
name: harness-new-feature
description: dev 起点の feature worktree を作成して並列開発レーンを 1 つ立ち上げる。`new-feature.sh` をラップ。「新機能を始める」「issue 着手」「feature ブランチを作る」「並列レーンに入る」等の文脈で発火。
---

# harness-new-feature

子 issue 番号と slug を受け取り、`<root>/lanes/feat-<issue>-<slug>/` に dev 起点の worktree を作る。

## 必須前提

- `<root>/.my-harness/scripts/new-feature.sh` が実行可能（bootstrap で配布済み）
- 現在の cwd がプロジェクトルート（`.my-harness/.config` がある場所）

## 呼び出し

```bash
cd <root>
bash .my-harness/scripts/new-feature.sh <issue-number> <slug>
```

例:
```bash
bash .my-harness/scripts/new-feature.sh 42 user-login
# → lanes/feat-42-user-login/ に worktree 作成、ブランチ feat/42-user-login（dev 起点）
```

## 完了後の作業フロー

1. `cd lanes/feat-<issue>-<slug>` で worktree に移動
2. `direnv allow`（初回のみ）
3. **TDD で実装**（`harness-tdd` skill 参照）
4. **規約遵守**（`harness-jsdoc` / `harness-hono-clean-arch` / `harness-drizzle-rules` 等）
5. `git add` / `git commit`（husky pre-commit が format/lint/test/secrets を弾く）
6. `git push` で feat ブランチを push
7. `gh pr create --base dev` で PR 作成（PR 先は **必ず dev**）

## 4 レーン並列の場合

`harness-team-lead` agent が 4 子 issue を 4 レーンに振り分ける。各レーンの engineer がこの skill で worktree を立ち上げる。

## 規約

- 起点ブランチは **必ず dev**（main / stage 起点は禁止、hotfix 除く）
- ブランチ命名は `feat/<issue>-<slug>` 統一
- マージ後は `git worktree remove lanes/feat-<issue>-<slug>` で掃除

## 関連

- hotfix 開始は `harness-new-hotfix`
- コンフリクト解消は `harness-resolve-conflict`
- dev 取込は `harness-sync-features`
