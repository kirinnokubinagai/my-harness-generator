# 汎用ハーネス（Generic Multi-Agent Harness）

Issue ドリブン / 4 レーン並列 / dev → stage → main の 3 段階デプロイを備えた、
**ワンコマンド対話セットアップ** の汎用開発ハーネス。

Web / iOS / Android の任意組合せ、DB（Cloudflare D1）、メール（Resend）はすべて **対話で選択**。
不要な機能は混入しない。

## 使い方（ワンコマンド）

```bash
# 任意のプロジェクトディレクトリで実行
bash <この harness ディレクトリ>/scripts/bootstrap.sh /path/to/project
```

スクリプトが対話で訊くこと:

| 質問 | 選択肢 |
|------|--------|
| プロジェクト名 | 自由入力（既定: ディレクトリ名） |
| Web を含める？ | y / n |
| iOS を含める？ | y / n |
| Android (Kotlin) を含める？ | y / n |
| DB を使う？ | y / n（y なら Cloudflare D1） |
| メール（Resend）を使う？ | y / n |
| Playwright を使う？ | y / n |
| Maestro を使う？ | y / n |
| Claude Code Action を使う？ | y / n |
| Claude Code Action の認証 | api / oauth |

回答は `.harness/.bootstrap.env` に保存され、後続スクリプトが参照します。

## 完了後の流れ（5 行）

```bash
cd <project>/dev
direnv allow                                        # Nix 環境を自動起動
pnpm install && pnpm exec husky                     # 依存 + フック設定
git remote add origin git@github.com:<owner>/<repo>.git && git push --all
bash .harness/scripts/setup-branch-protection.sh <owner>/<repo>
bash .harness/scripts/setup-secrets.sh <owner>/<repo>   # 必要 secrets だけ対話で
```

これで dev / stage / main の保護、auto-merge、必須 status check、CI 全部が稼働します。

## 構成

```
<project>/
├── .bare/                      ベアリポ（git は .git ファイル経由）
├── dev/   stage/   main/       worktree（dev だけで作業）
├── lanes/feat-<n>-<slug>/      feature 用 worktree（4 レーン並列）
└── dev/.harness/               このハーネス自体（更新も可能）
```

## 主要スクリプト（全部シェル、エージェントは考えない）

| スクリプト | 役割 |
|-----------|------|
| `bootstrap.sh` | **エントリポイント**。対話で構成決定 → bare/worktree → テンプレ配布 |
| `setup-common.sh` | Biome / Husky / Nix / gitleaks / GitHub テンプレ配布 |
| `setup-platforms.sh` | bootstrap.env を読み web / ios / android / db / email を選択配布 |
| `generate-package-json.sh` | 選択に応じた最小依存の package.json を jq で組み立て |
| `configure-claude-action.sh` | Claude Code Action の認証分岐（API key / OAuth） |
| `setup-branch-protection.sh` | force-push 禁止、必須レビュー / status checks、auto-merge 有効化 |
| `setup-secrets.sh` | 選択された機能に必要な secrets / variables を対話で `gh` 登録 |
| `new-feature.sh <issue> <slug>` | dev 起点の feature worktree を作成 |
| `new-hotfix.sh <issue> <slug>` | main 起点の hotfix worktree を作成 |
| `resolve-conflict.sh` | rebase / reset 禁止のマージコミット解消 |
| `sync-features-with-dev.sh` | hotfix 逆流後に全 feature worktree を dev に同期 |
| `migrate-after-restore.sh` | 本番 DB バックアップを stage に復元したあと、stage 追加マイグレーションを再適用 |
| `check-migration-conflict.sh` | 同一親 issue 配下の複数子で migration が同時に走らないかチェック |
| `check-forbidden-patterns.sh` | 環境変数キー直書き / URL 認証 / 平文 .env を検出（pre-commit + CI） |
| `anonymize-pii.sh` | stage 復元前の PII マスキング（雛形） |

## 規約（要点）

- **TDD 厳格**: 先にテストを書いて赤を確認、最小実装で緑、それからリファクタ。E2E も同様。
- **Hono Clean Arch**: domain → application → infrastructure / interfaces。
- **Drizzle のみ、`drizzle-kit migrate` のみ**（`push` 禁止）。
- **Nix pure**: `direnv allow` で自動。Apple toolchain（Xcode / iOS Simulator）のみ例外。
- **AI 風デザイン禁止**: Lucide Icons のみ、グラデーション・ネオン・絵文字禁止。
- **JSDoc / TSDoc 必須、関数内コメント禁止、説明はすべて日本語**。
- **Git**: rebase / reset --hard / push --force 禁止。コンフリクトはマージコミット。

## 4 レーン並列フロー

team-lead が GitHub issue を 4 レーンに振り分け、各レーンで:

```
analyst-N → engineer-N（TDD で実装）→ e2e-reviewer-N（必要なら）→ reviewer-N
                ↑                                                    ↓
                └─────────────── 修正フィードバック ─────────────────┘
```

修正 / 進捗 / コンフリクトは analyst-N 経由で team-lead に集約。
team-lead はコードを書かず、配備とマージ承認に専念。

## 詳細

- 作業フロー: [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)
- Hotfix: [`docs/HOTFIX.md`](./docs/HOTFIX.md)
- セキュリティ: [`docs/SECURITY.md`](./docs/SECURITY.md)
- インフラ: [`docs/INFRA.md`](./docs/INFRA.md)
- iOS DAST: [`docs/IOS_DAST.md`](./docs/IOS_DAST.md)
- エンジニア規約: [`docs/ENGINEER_STANDARDS.md`](./docs/ENGINEER_STANDARDS.md)
- セットアップ詳細: [`docs/SETUP.md`](./docs/SETUP.md)
