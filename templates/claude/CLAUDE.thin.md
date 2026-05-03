# プロジェクト固有 Claude 設定（薄い版）

このプロジェクトは [my-harness-generator](https://github.com/anonymous/my-harness-generator) で生成されました。

## skills を使ってください

詳細なルールは個別の **`harness-*` skill** に分割されています。Claude（あなた）は、状況に応じて必要な skill だけを必要なときに読み込んでください（lazy load）。  
これにより常駐コンテキストを最小化しつつ、規律を保ちます。

| やること | 使う skill |
|----------|-----------|
| テストを書く / バグ修正 / リファクタ | `harness-tdd` |
| Hono / API 層を実装 | `harness-hono-clean-arch` |
| DB スキーマ / マイグレーション | `harness-drizzle-rules` |
| コマンド実行 / 環境構築 | `harness-nix-pure` |
| UI / コンポーネント / 配色 | `harness-design-rules` |
| 関数 / 型 / コメント / 言語 | `harness-jsdoc` |
| Git 操作 / コンフリクト | `harness-git-discipline` |
| 環境変数 / 機密値の扱い | `harness-no-hardcoded-secrets` |
| Codex に第二意見を求める | `harness-codex-consult` |
| 機密値をマスクする | `harness-mask` |

## ハーネス内のスクリプト（shell は skills 経由で呼ばれる）

`<root>/.my-harness/scripts/*.sh` 配下に各種シェルスクリプトがあるが、Claude が考えずに済むよう **すべて skill 経由で呼ばれる設計**。

- 新 feature 開始: skill 経由で `new-feature.sh`
- コンフリクト解消: skill 経由で `resolve-conflict.sh`
- Codex 相談: skill `harness-codex-consult` から `codex-ask.sh`
- マスキング: skill `harness-mask` から `mask-secrets.sh`

## 機密扱いの自動化

`UserPromptSubmit` フックがユーザー入力を **マスク済で `dev/docs/talk/<日付>.md` に自動追記** する。  
Claude が書き忘れても会話ログは残る（漏れ防止）。  
pre-commit が `gitleaks` + `check-forbidden-patterns.sh` で二重防御。

## 既知の制約

`/my-harness-init` 完了後、新しい `dev/.claude/CLAUDE.md` と skills を **完全に有効化するには Claude Code を再起動**するか `/clear` を実行してください。  
（mid-session の動的再読込は Claude Code 標準では不可）
