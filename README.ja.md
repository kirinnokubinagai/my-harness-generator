# my-harness-generator（日本語版）

> 「何を作るかぼんやりしている」状態から、本番運用可能なフルスキャフォルディング済プロジェクトを 1 回の会話で立ち上げる Claude Code プラグイン。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-orange.svg)](https://code.claude.com)
[![English](https://img.shields.io/badge/lang-English-blue.svg)](./README.md)

[English version / 英語版はこちら](./README.md)

---

## このプラグインがやること

世にある「スターターキット」はボイラープレートをくれるが、**本当に難しい部分**（要件定義、アーキテクチャ選定、レーン割当、セキュリティ規律）はあなた任せ。本プラグインは Claude が**構造化されたインタビュー**であなたから引き出し、必要なら OpenAI Codex に第二意見を求め、ロゴ・UI モックを生成し、技術スタックを決定し、ブランチ保護・CI・hooks・4 レーン並列開発の規約までセットされた完全なモノレポを 1 つのスラッシュコマンドから生成する。

生成された直後のプロジェクトでは:

- 最初のコミットがすでに緑（CI / テスト / lint がすべて通る）。
- `main` / `stage` / `dev` にブランチ保護が適用され、直接 push は不可能。
- Claude との会話はすべて自動でマスク済みのまま `dev/docs/talk/` に記録される。
- 「次にやること」が常に明文化されている — 「で、次は？」と迷うことがない。

## ハイライト

- **`/my-harness-init`** — 仕様書の生成と `bootstrap.sh` 実行までを一気通貫で行う対話インタビュー。
- **Codex CLI 連携（任意）** — session resume による真のマルチターン対話。ロゴ・UI モックを `gpt-image-2` で生成。さらに `engineer` / `e2e-reviewer` / `reviewer` の subagent 役割を **役割ごとに独立に Codex へ委譲可能**（master switch は `USE_CODEX`、各役割は `USE_CODEX_<ROLE>` で y/n 切替）。
- **ワンコマンド bootstrap** — bare git + `dev`/`stage`/`main` worktree + Husky + Biome + Nix flake + GitHub Actions 9 本 + Drizzle + Resend + Playwright + Maestro。
- **プラットフォームごとに独立してフレームワーク選択可能** — Web（`nextjs` / `tanstack`）、iOS（`swift` / `expo` / `flutter`）、Android（`kotlin` / `expo` / `flutter`）、Desktop（`tauri` / `electron` + macOS/Windows/Linux）、バックエンド（`hono` / `gin` / `rust`）、DB（`d1` / `postgres` / `mysql` / `sqlite`）。1 つの選択が他のプラットフォームに波及しない。
- **4 レーン並列開発** — `harness-team-lead` agent が issue を 4 レーンに振り分け、各レーンが analyst → engineer → e2e-reviewer → reviewer のフローで並列実装。
- **自動機密マスキング** — `UserPromptSubmit` フックがユーザー入力を `mask-secrets.sh`（9 パターン）に通して `dev/docs/talk/<日付>.md` に記録。
- **21 個の skill を lazy load** — TDD / Hono Clean Architecture / Drizzle migrate-only / Nix pure / デザイン規律 / JSDoc / Git 規律 / ハードコード機密検出 ほか。
- **GitHub Issue モード切替（任意）** — init 時に `gh issue create` を使うか、ローカル `dev/docs/task/*.md` で管理するかを選択。

## インストール

### 前提条件

- Claude Code（最新版）
- `git` / `bash` / `jq` / `direnv`（Nix dev shell 自動切替用）
- 任意: Codex 連携を使うなら `npm install -g @openai/codex` + `codex login`

### プラグイン本体のインストール

Claude Code 内で:

```
/plugin marketplace add https://github.com/kirinnokubinagai/my-harness-generator
/plugin install my-harness@my-harness-generator
```

その後、新しい skills と hooks を有効化するため **Claude Code を完全再起動**（または `/clear`）してください。

### 動作確認

```
/my-harness-init
```

インタビューが起動して最初の質問が表示されればインストール成功です。中断したい場合は `Esc`（または会話を閉じる）でキャンセルできます。何も生成されません。

## クイックスタート

新規プロジェクトを始めるときに必要なコマンドは `/my-harness-init` ひとつだけ。以下のフェーズを 1 ターン 1 問で進めます。各 Q&A は **マスク済み** で `dev/docs/spec/` と `dev/docs/talk/` に自動保存されます。

| フェーズ | 決めること |
|---------|-----------|
| **Setup** | プロジェクトのルートパス / slug / Codex 連携 y/n / タスク管理方式（GitHub Issue or ローカル） / 個人 `~/.claude/CLAUDE.md` を引き継ぐか |
| **Problem** | 誰のどんな課題か、既存サービスではダメな理由、成功の定義 |
| **Personas** | ユーザータイプ、利用シーン、技術リテラシ |
| **Features** | MVP 境界と必須機能 5〜10 個の優先順位 |
| **Stack** | Web / iOS / Android、DB、メール、E2E の選択 |
| **Data model** | エンティティ・関係・PII の扱い（mermaid ER 図含む） |
| **Visual** | ロゴ 3 案 + 主要画面 UI モック 3〜5 個（Codex `gpt-image-2`）。モックを見て要件が変わったら前のフェーズに戻る |
| **Finalize** | 仕様の最終 cross-check、`bootstrap.sh` 実行、初期 issue / task ファイル生成（レーン割当含む） |

bootstrap 完了後:

```bash
cd ~/<project>/dev
direnv allow
nix develop --command pnpm install
nix develop --command pnpm exec husky
nix develop --command pnpm exec vitest run    # health.test.ts が緑になればOK
```

GitHub に push:

```bash
git remote add origin git@github.com:<owner>/<repo>.git
git push --all origin
bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>
```

## プロジェクトの 6 段階ライフサイクル

このプラグインが強制するアイデアから本番までのフロー全体。最初の 3 段階は `/my-harness-init` の中で連続して行われ、4 段階目以降にそれぞれ専用コマンドがあります。

| 段階 | 内容 | 主コマンド |
|------|------|----------|
| 1. Spec | 問題定義 / ペルソナ / 機能 / 技術スタック / データモデル | `/my-harness-init`（Problem〜Data model） |
| 2. Design | ロゴ + UI モック + 仕様 iteration | `/my-harness-init`（Visual フェーズ） |
| 3. Tasks | issue / task ファイル生成、4 レーンへのファイル所有割当、bootstrap 実行 | `/my-harness-init`（Finalize フェーズ） |
| 4. Implementation | 4 レーン並列実装、各 issue を fresh subagent で処理 | `/harness-new-feature <issue>` |
| 5. Deploy setup | Terraform infra（Cloudflare D1 / R2 / Pages）、wrangler bindings、GitHub secrets / vars、fastlane（iOS） | `/harness-deploy-setup` |
| 6. Deploy | `dev` → `stage`（自動 + 人間ラベル）→ `main`（canary 10% → 100%） | `/harness-deploy-execute` |

緊急修正用の別経路（`/harness-new-hotfix`）もあります。次の「日常コマンド」を参照。

## 日常コマンド

init 後の開発で使うコマンド一覧:

| やりたいこと | コマンド |
|-------------|---------|
| 新規 feature を 4 レーン並列で開始 | `/harness-new-feature <issue#> <slug>` |
| 緊急 hotfix（main 起点） | `/harness-new-hotfix <issue#> <slug>` |
| コンフリクト解消（rebase 禁止） | `/harness-resolve-conflict` |
| hotfix 後に全 feature を dev 同期 | `/harness-sync-features` |
| Codex に第二意見を求める | `/harness-codex-consult`（または「Codex に聞いて」） |
| 機密チェック（手動） | `/harness-check-secrets` |
| ブランチ保護を一括適用 | `/harness-branch-protection` |
| Terraform デプロイ設定を生成 | `/harness-deploy-setup` |
| 段階的本番デプロイを実行 | `/harness-deploy-execute` |

## 自動発火する規約 skill

以下は会話の文脈に応じて**自動で**読み込まれる skill。あなたが明示的に呼ぶ必要はありません。

| skill | 発火するとき |
|-------|-------------|
| `harness-tdd` | テスト記述 / バグ修正 / リファクタ / 振る舞い変更 |
| `harness-hono-clean-arch` | Hono ルート / サービス / リポジトリ実装 |
| `harness-drizzle-rules` | スキーマ変更 / マイグレーション（migrate-only 強制、`drizzle-kit push` 禁止） |
| `harness-nix-pure` | コマンド実行 / ツールインストール（`brew install` 禁止、`nix develop --command` 必須） |
| `harness-design-rules` | UI コンポーネント / 配色 / アイコン（Lucide のみ、AI 風グラデ禁止） |
| `harness-jsdoc` | 関数 / 型 / コメント記述（JSDoc 必須、関数内コメント禁止） |
| `harness-git-discipline` | git 操作 / コンフリクト（`rebase` / `reset --hard` / `push --force` 禁止） |
| `harness-no-hardcoded-secrets` | 環境変数 / API キー / `.env` 操作 |
| `harness-mask` | 機密値マスク手動実行 |
| `harness-codex-consult` | 「Codex に聞いて」「セカンドオピニオン」 |

## 全 skill 一覧（21 個）

| 種別 | skill | 用途 |
|------|-------|------|
| エントリ | `my-harness-init` | 新規プロジェクトをゼロから（インタビュー → bootstrap）。既存の `.my-harness/init-state.json` を検出すると保存済フェーズから再開する。 |
| 規約 | `harness-tdd` | Red-Green-Refactor 強制 |
| 規約 | `harness-hono-clean-arch` | Hono の 4 層 Clean Architecture |
| 規約 | `harness-drizzle-rules` | Drizzle migrate-only、マイグレーション命名規約 |
| 規約 | `harness-nix-pure` | Nix flake pure 環境、direnv 自動切替 |
| 規約 | `harness-design-rules` | AI 風デザイン禁止、Lucide のみ、WCAG AA |
| 規約 | `harness-jsdoc` | 全 export に JSDoc / TSDoc 必須、説明は日本語 |
| 規約 | `harness-git-discipline` | rebase / reset / force-push 禁止、merge コミットのみ |
| 規約 | `harness-no-hardcoded-secrets` | env vars / SOPS のみ許可、ハードコード禁止 |
| 規約 | `harness-mask` | 9 パターンの機密マスキング |
| 規約 | `harness-codex-consult` | `codex-ask.sh` ラッパー、Codex 第二意見 |
| 操作 | `harness-new-feature` | dev 起点の feature worktree 作成 |
| 操作 | `harness-new-hotfix` | main 起点の hotfix worktree 作成 |
| 操作 | `harness-resolve-conflict` | merge コミットのみでコンフリクト解消 |
| 操作 | `harness-sync-features` | 全 feature ブランチに dev を back-merge |
| 操作 | `harness-check-codex-auth` | Codex CLI のインストール / ログイン状態確認 |
| 操作 | `harness-check-secrets` | 禁止パターンスキャン |
| 操作 | `harness-setup-secrets` | GitHub Secrets / Variables を対話登録 |
| 操作 | `harness-branch-protection` | ブランチ保護を一括適用 |
| 操作 | `harness-deploy-setup` | Terraform / wrangler / fastlane 生成 |
| 操作 | `harness-deploy-execute` | dev → stage → main 段階デプロイ |

## アーキテクチャ図

```
[ユーザー入力]
    ↓
[UserPromptSubmit hook] → mask-secrets.sh → dev/docs/talk/<日付>.md
    ↓
[Claude]
    ↓ lazy load
[harness-* skill]（21 個から自動選択）
    ↓
[shell スクリプト]
    ↓
[実装]
    ↓
[Stop hook] → assistant 応答抽出 → マスク → dev/docs/talk/
    ↓
[git pre-commit] → gitleaks + check-forbidden-patterns（二重防御）
    ↓
[push]
```

## 生成されるプロジェクト構造

```
<project>/
├── .bare/                              ベアリポジトリ
├── .git → .bare                        gitfile（gitdir: ./.bare）
├── .my-harness/.config                 選択した設定（team-shared、git 管理）
├── .my-harness/codex-sessions/         Codex session ID（gitignore）
├── dev/   stage/   main/               worktree（dev だけで作業）
├── lanes/feat-<n>-<slug>/              feature worktree（最大 4 レーン並列）
└── lanes/hotfix-<n>-<slug>/            hotfix worktree（main 起点）
    ├── .claude/                        USE_GLOBAL_CLAUDE=no の場合のみ
    ├── docs/{spec,design,talk,task}/   仕様 / モック / 会話ログ / タスク
    ├── .my-harness/                    plugin 本体のコピー
    ├── flake.nix .envrc                Nix pure 環境
    ├── biome.json package.json         開発ツール設定
    ├── .husky/                         pre-commit / pre-push / commit-msg
    └── .github/
        ├── workflows/                  CI 9 本
        └── scripts/maybe-create-issue.js   GitHub Issue 分岐ヘルパー
```

## ブランチ規約

| from → to | 必要条件 |
|-----------|---------|
| `feat/*` → `dev` | PR + format / lint / test / typecheck 全 green |
| `dev` → `stage` | 人間承認 + OWASP ZAP + Playwright + Maestro + Semgrep + Trivy 緑 |
| `stage` → `main` | 人間承認 + 全ゲート緑 + canary 10% → 100% |
| `hotfix/*` → `main` | 緊急承認 + 最小 test/lint/format（post-merge で ZAP/E2E 即時実行） |

`main` / `stage` への直接 push は pre-push フック + GitHub branch protection で **二重に遮断**（後者は `/harness-branch-protection` で適用）。

## 強制される規約

- **TDD 厳格** — Red-Green-Refactor。テスト無しで書いた本番コードは削除して書き直す。
- **Hono Clean Architecture** — `domain ← application ← infrastructure / interfaces` の依存方向を厳守。
- **Drizzle migrate のみ** — `drizzle-kit push` 禁止（履歴が残らずロールバック不可のため）。
- **Nix pure** — 全ツール実行は `nix develop --command` 経由、`brew install` 禁止。
- **AI 風デザイン禁止** — Lucide Icons のみ、グラデ / ネオン / 絵文字禁止、WCAG AA、UX 心理学 47 原則の主要 10 を必須適用。
- **JSDoc / TSDoc 必須** — 全 export に。関数内コメント禁止。説明はすべて日本語。
- **Git 規律** — `rebase` / `reset --hard` / `push --force` 禁止。コンフリクトは merge コミットで解消。

## Fresh-agent-per-issue 原則

各 issue は **完全に新規の subagent context** で処理されます。`harness-team-lead` は engineer / analyst / e2e-reviewer / reviewer を **必ず `Task(subagent_type=..., prompt=...)` で fresh spawn** し、`SendMessage` で前回の subagent を継続呼び出ししません。これにより:

- 前 issue の判断や命名が現 issue に染み込まないことを保証。
- context 累積によるトークンコスト増を抑制。
- 各レーンが真に独立して動く（lane 2 で起きたことが lane 3 に影響しない）。

team-lead 自身の context が重くなったら（issue 5〜10 個ごと）、進捗を `.my-harness/team-state.json` に保存してユーザーに「`/clear` してから team-state.json を読み直して再開してください」と案内します。

## 設定オプション

`/my-harness-init` のインタビュー結果は `<root>/.my-harness/.config` に保存されます:

```bash
PROJECT_NAME=todo-app
USE_WEB=yes
WEB_KIND=nextjs               # USE_WEB=yes のときのみ（nextjs | tanstack）
USE_IOS=no
IOS_KIND=swift                # USE_IOS=yes のときのみ（swift | expo | flutter）
USE_ANDROID=no
ANDROID_KIND=kotlin           # USE_ANDROID=yes のときのみ（kotlin | expo | flutter）
USE_DESKTOP=no
DESKTOP_KIND=tauri            # USE_DESKTOP=yes のときのみ（tauri | electron）
DESKTOP_OS=macos,windows,linux  # USE_DESKTOP=yes のときのみ
USE_BACKEND=yes
BACKEND_KIND=hono             # USE_BACKEND=yes のときのみ（hono | gin | rust）
USE_DB=yes
DB_KIND=d1                    # USE_DB=yes のときのみ（d1 | postgres | mysql | sqlite）
USE_EMAIL=yes                 # Resend + パスワードリセットフロー
USE_PLAYWRIGHT=yes
USE_MAESTRO=no
USE_CLAUDE_ACTION=yes         # PR レビューに Claude Code Action
CLAUDE_AUTH=oauth             # サブスクリプション or "api"（API キー）
USE_GLOBAL_CLAUDE=yes         # ~/.claude/CLAUDE.md を引き継ぐ or プロジェクト独立
USE_GITHUB_ISSUES=yes         # gh issue or "no"（ローカル docs/task/）
CODEX_SESSION=my-harness-init
USE_CODEX_ENGINEER=yes        # engineer subagent を Codex に委譲（USE_CODEX=yes のときのみ意味あり）
USE_CODEX_E2E_REVIEWER=yes    # E2E テスト実行を Codex に委譲
USE_CODEX_REVIEWER=yes        # 規約レビューを Codex に委譲
ON_CODEX_AUTH_FAIL=pause      # 既定: 認証/サブスク切れ時にユーザー通知＋待機、re-login 後 resume。fail なら即失敗
```

非対話で再実行:

```bash
bash bootstrap.sh <root> --config <root>/.my-harness/.config
```

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| skill が発火しない | Claude Code を完全再起動 / `/clear` |
| hook が `dev/docs/talk/` に書かない | `~/.claude/settings.json` にプラグインの `UserPromptSubmit` / `Stop` hook が登録されているか確認。`/doctor` でスキーマ検証 |
| Codex 認証エラー | `/harness-check-codex-auth` → `codex login` |
| Codex subagent が `blocked-codex-auth`（実行中に login 切れ）で停止 | `codex login` を実行 → team-lead に「resume」と返信。同じ Codex session がサーバー側で保持されているため、前ターンの context を保ったまま再開できる |
| Codex subagent が `subscription-or-quota` 理由で停止 | (a) ChatGPT サブスクを再有効化、(b) `OPENAI_API_KEY` を export して pay-per-use に切替、(c) `.my-harness/.config` で `USE_CODEX_<ROLE>=no` にして Claude フォールバック の 3 つから選んで「resume」 |
| hotfix 逆流でコンフリクト | `/harness-resolve-conflict` を使う（rebase 禁止） |
| 誤って `drizzle-kit push` してしまった | revert → `drizzle-kit generate --name <具体名>` → `wrangler d1 migrations apply` |
| プラグインを更新したい | `/plugin marketplace update` → `/plugin install my-harness@my-harness-generator` |
| dev に worktree 残骸 | `git worktree prune`（bootstrap が自動でやる） |
| `direnv: error Path 'flake.nix' is not tracked by Git` | `git add flake.nix && git commit`（bootstrap が自動でやる） |

## よくある質問

**Q: 既存プロジェクトに後から導入できる？**
A: できますが推奨しません。`/my-harness-init` は新規前提。既存に当てたい場合は `.my-harness/.config` を手動で書いて `bootstrap.sh --config` を呼べば動きますが、bare git の付け替えなど破壊的変更が伴います。

**Q: Codex CLI 必須？**
A: いいえ、任意です。Setup フェーズで `n` を選べば Claude 単独で全フェーズ進みます（画像生成だけスキップ）。

**Q: チームで使うとき個人差が出ない？**
A: Setup で `USE_GLOBAL_CLAUDE=no` を選ぶと `dev/.claude/CLAUDE.md` にプロジェクト専用指示が配置され、個人の `~/.claude/CLAUDE.md` の影響を最小化できます（Claude Code 仕様上 100% isolate は不可）。

**Q: 4 レーン並列って具体的にどう動く？**
A: `harness-team-lead` が issue を **ファイル所有が重ならない** ように `lane/1`〜`lane/4` に振り分け、各レーンが independent worktree で analyst → engineer → e2e-reviewer → reviewer を順に走らせます。詳細は [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)。

**Q: `dev/docs/talk/` に変なこと書いたらリポジトリに残る？**
A: 残ります（`mask-secrets.sh` で機密はマスクされますが、内容自体は git 管理対象）。private repo 推奨。「talk を git 管理したくない」場合は `dev/.gitignore` に `dev/docs/talk/` を追加してください（推奨方針からは外れます）。

**Q: プラグイン自体を更新したい**
A: `cd ~/.claude/plugins/cache/.../my-harness && git pull` ではなく、Claude Code の `/plugin marketplace update` → `/plugin install my-harness@my-harness-generator` を使ってください。

## 詳細ドキュメント

- 作業フロー: [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)
- Hotfix 手順: [`docs/HOTFIX.md`](./docs/HOTFIX.md)
- セキュリティ: [`docs/SECURITY.md`](./docs/SECURITY.md)
- インフラ: [`docs/INFRA.md`](./docs/INFRA.md)
- iOS DAST: [`docs/IOS_DAST.md`](./docs/IOS_DAST.md)
- エンジニア規約: [`docs/ENGINEER_STANDARDS.md`](./docs/ENGINEER_STANDARDS.md)
- セットアップ詳細: [`docs/SETUP.md`](./docs/SETUP.md)

## 開発に貢献する

PR 歓迎。プラグインは自分自身の規約を自分の開発にも適用しています:

```bash
git clone https://github.com/kirinnokubinagai/my-harness-generator
cd my-harness-generator
# ローカルマーケットプレースとして追加して動作確認
/plugin marketplace add ./
/plugin install my-harness@my-harness-generator
```

- shell スクリプトは `bash -n`（構文チェック）を通ること必須。
- 全 `SKILL.md` は frontmatter `name` + `description` 必須。
- コミットは Conventional Commits + 日本語本文。
- レーン規約は [`docs/WORKFLOW.md`](./docs/WORKFLOW.md) を参照。

## ライセンス

MIT — [`LICENSE`](./LICENSE) を参照。
