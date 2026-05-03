---
name: harness-codex-consult
description: Codex（OpenAI）に第二意見を求めるためのブリッジ。codex-ask.sh をラップし、role / context / session を簡潔に渡せる。「Codex に聞いて」「セカンドオピニオン」「Codex でレビュー」「画像生成して」等の文脈で発火。
---

# harness-codex-consult

Claude → Codex（外部 LLM）への対話を、`codex-ask.sh` ラッパー shell 経由で実行する skill。

## 前提

- `~/my-harness-generator/scripts/codex-ask.sh` が実行可能
- `codex` CLI がインストールされ `codex login` 済（`check-codex-auth.sh` で確認可能）
- `<root>/.my-harness/.config` に `USE_CODEX=yes` が設定されている

## 標準呼び出し

```bash
~/my-harness-generator/scripts/codex-ask.sh \
  --role <role> \
  --out <root>/.my-harness/codex-<topic>.md \
  --log <root>/.my-harness/codex.jsonl \
  "質問本文（複数行可、ヒアドキュメント可）"
```

session は `~/.codex-active-session` にプロジェクトルートが登録されていれば **自動 resume**。
`/my-harness-init` の段階 0 で `--set-active <root>` 済みなら何もしなくて良い。

## role の選び方

| 状況 | role |
|------|------|
| 前提を疑う、対立仮説を出す | `critic` |
| 要件のあいまい・矛盾検出 | `analyst` |
| 順序・依存・リスク整理 | `planner` |
| 設計妥当性・トレードオフ | `architect` |
| デザイン提案 / 画像生成 | `designer` |
| 仕様書の論理レビュー | `code-reviewer` |
| セキュリティ観点 | `security-reviewer` |
| TDD コーチング | `tdd` |

## 使用例

### 仕様レビュー
```bash
codex-ask.sh \
  --role code-reviewer \
  --context dev/docs/spec/01-problem.md dev/docs/spec/02-personas.md -- \
  "仕様の論理矛盾、機能と技術の不整合を指摘してください。"
```

### 画像生成（普通の対話で頼むだけ）
```bash
codex-ask.sh \
  --role designer \
  "todo-app のロゴを 3 案、各 PNG として以下に保存してください。
スタイル: 信頼・シンプル・温かい
主色: #14b8a6
保存先:
- dev/docs/design/logo-1.png
- dev/docs/design/logo-2.png
- dev/docs/design/logo-3.png"
```

Codex が画像生成ツールを持っていれば実行・保存してくれる。

### アーキテクチャ妥当性
```bash
codex-ask.sh \
  --role architect \
  --out dev/docs/spec/codex-arch-review.md \
  "Hono + Cloudflare D1 + Drizzle のスタックで、
ユーザー認証 + 課金 + Resend メール の MVP を作るとき、
モジュール境界をどう切るのが妥当か？"
```

## session 制御

```bash
codex-ask.sh --set-active <project-root>     # active プロジェクト登録
codex-ask.sh --clear-active                  # 破棄
codex-ask.sh --session brainstorm "..."      # 名前付き session
codex-ask.sh --session brainstorm --reset-session  # 破棄
```

## 失敗時のハンドリング

- Codex 未インストール → exit 127、`npm i -g @openai/codex` を案内
- 未ログイン → `bash ~/my-harness-generator/scripts/check-codex-auth.sh` で確認、`codex login` を促す
- session 切れ → `--reset-session` で再作成

## ベスプラ

- 1 ターン 1 観点（あれもこれも聞かない）
- `--context` で関連ファイルを添付（zip 不要、shell が文字列で添付）
- 結果は `--out` でファイル保存し、Read で読み直すのが確実
- 画像生成は普通の対話文で頼むだけ（`--image` のような専用フラグは無い）
