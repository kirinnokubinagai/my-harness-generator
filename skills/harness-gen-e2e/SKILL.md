---
name: harness-gen-e2e
description: dev/docs/spec/features.md の各機能セクションから Playwright E2E テストを Codex で生成する。spec が「ログイン後にダッシュボードに遷移する」と書いてある時点でテストは事実上決まっているので、人間が書き起こす作業を省く。Codex (USE_CODEX_E2E=yes) または Claude フォールバック。
---

# harness-gen-e2e

## いつ使うか

- 新機能の spec を書き終え、TDD で test-first を実施したいが手作業が辛い
- 既存 spec を見直して E2E カバレッジが揃っているか確認したい
- 仕様変更時にテストの追従漏れを検出したい

## 動作

```bash
bash $CLAUDE_PLUGIN_ROOT/scripts/gen-e2e.sh                     # 全機能
bash $CLAUDE_PLUGIN_ROOT/scripts/gen-e2e.sh --feature "ログイン"   # 単一機能
bash $CLAUDE_PLUGIN_ROOT/scripts/gen-e2e.sh --dry-run            # 生成プロンプトのみ表示
```

スクリプトは:

1. `dev/docs/spec/features.md` を読み、`## Feature: <name>` セクションごとに分割
2. `prompts/spec-to-e2e.md` のテンプレートに spec 本文を埋め込み
3. Codex (`codex-ask.sh --role harness-engineer`) に渡してテストコードを生成
4. `dev/tests/e2e/<slug>.spec.ts` として保存 (既存あれば skip)
5. lane エージェントが `pnpm test:e2e` で実行できる状態に

## 生成ルール

- happy path 1 件 + sad path 2 件以上 を最低基準
- セレクタは `data-testid` 優先、なければ role-based / text-based
- API モックではなく実 backend を叩く (stage 環境想定)
- assertion は **必ず** ユーザー観点 — 「URL が変わる」「特定のテキストが表示される」「button が disabled になる」
- 認証フローは `tests/e2e/fixtures/auth.ts` の helper を使う前提 (lane エージェントが先に整備)

## 失敗時の挙動

Codex auth 失敗 / quota 切れ → 通常の harness-team-lead と同じく `blocked-codex-auth` / `subscription-or-quota` 状態を返し、ユーザーが「resume」と言うまで待機。`USE_CODEX_E2E=no` 設定なら Claude が直接生成する。

## 関連ファイル

- `scripts/gen-e2e.sh` — 実装
- `prompts/spec-to-e2e.md` — Codex プロンプトテンプレート
- `rules/tdd.md` — 生成テストが満たすべき作法
