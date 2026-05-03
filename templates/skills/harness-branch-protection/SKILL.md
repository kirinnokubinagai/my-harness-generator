---
name: harness-branch-protection
description: GitHub の branch protection を main / stage / dev に一括適用する。`setup-branch-protection.sh` をラップ。force-push 禁止 / 必須レビュー / 必須 status checks / auto-merge 有効化 / merge コミット保持を強制。「branch protection」「force push 禁止」「PR 必須」等の文脈で発火。
---

# harness-branch-protection

ハーネス標準のブランチ保護を `gh` CLI 経由で一括設定。**初回 1 回**、リポジトリ作成 + push 後に実行する。

## 必須前提

- `gh auth status` が OK
- リモート origin にプッシュ済み（main / stage / dev のリモート参照が存在）

## 呼び出し

```bash
cd <root>
bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
```

## 適用される保護（全ブランチ共通）

- `allow_force_pushes=false`（**force-push 禁止**）
- `allow_deletions=false`（ブランチ削除禁止）
- `required_pull_request_reviews` 必須（main=2 名 / stage=1 / dev=1）
- `dismiss_stale_reviews=true`（コミット追加でレビュー無効化）
- `require_code_owner_reviews=true`
- `required_conversation_resolution=true`
- 必須 status checks: `quality`, `e2e`, `security`, `claude-review`

## リポジトリ設定

- `allow_auto_merge=true`（auto-merge 機能有効）
- `allow_merge_commit=true`（merge commit 保持）
- `allow_squash_merge=false`（squash 禁止、history 改変）
- `allow_rebase_merge=false`（rebase 禁止、`harness-git-discipline` 準拠）
- `delete_branch_on_merge=true`（マージ後クリーンアップ）

## 検証

```bash
gh api "repos/<owner>/<repo>/branches/main/protection" | jq .
```

## なぜこれが必要か

`harness-git-discipline` skill の規約（rebase / reset / force-push 禁止）を **GitHub サーバ側でも強制** することで、ローカルで `--no-verify` で迂回されても push が止まる。最後の砦。

## 関連

- Git 規律: `harness-git-discipline`
- secrets 設定: `harness-setup-secrets`
- bootstrap 完了 → branch protection → secrets の順で 1 回ずつ
