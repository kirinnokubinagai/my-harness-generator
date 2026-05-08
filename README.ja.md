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

`/my-harness-init` の最初の質問で英語（English）または日本語（Japanese）を選択します。それ以降に生成されるすべての内容はその選択に従います。

新規プロジェクトを始めるときに必要なコマンドは `/my-harness-init` ひとつだけ。以下の 9 フェーズを 1 ターン 1 問で進めます。各 Q&A は **マスク済み** で `dev/docs/spec/` と `dev/docs/talk/` に自動保存されます。フェーズ順は意図的に「深掘り → 構造 → 機能 → **モックを先に作ってからツール選定** → データモデル」となっており、画面に何が必要かを見てから DB / Next.js / パッケージマネージャー等を決めます。

| # | フェーズ | 決めること |
|---|---------|-----------|
| 0 | **Language** | 以降のインタビューを英語で進めるか日本語で進めるか |
| 1 | **Setup** | プロジェクトのルートパス / Codex 連携 y/n / 個人グローバル CLAUDE.md 引き継ぎ y/n / タスク管理方式（GitHub Issue or ローカル） |
| 2 | **Discovery** | 自由対話で深掘り — 失敗パターン・反対者・スケール限界・信頼根拠・差別化・運用 6 カ月後、といった**支柱になる制約**を引き出す |
| 3 | **Structure** | アーキテクチャ（client-server / serverless / pure P2P / hybrid P2P）とプラットフォーム複数選択（web / desktop / mobile + iOS / Android）のみ |
| 4 | **Features** | v1 の完全な機能リスト — 各機能ごとに 「経路 / 失敗 / 観測 / オンボード / 上級者ショートカット / 空状態 / 失敗復旧 / レイテンシ予算」 を深掘り |
| 5 | **Visual** | ロゴ 3 案 + 選択した各プラットフォーム別に UI モック 3〜5 個（Codex `gpt-image-2`）。各モック表示後に「足りない要素 / 紛らわしい要素 / 隠れた制約」を必ず質問。モックがソースオブトゥルース |
| 6 | **Tools** | フレームワーク（プラットフォーム別）/ バックエンド / DB / パッケージマネージャー / メール / E2E / Claude Code Action — どの質問も承認済みモックを参照する（「ダッシュボードモックがリアルタイムを要求しているので…」など） |
| 7 | **Data model** | エンティティ・関係・PII の扱い（mermaid ER 図）— 各エンティティを「ライフサイクル / GDPR / 権限 / 規模実態 / マイグレーション」で深掘り |
| 8 | **Bootstrap** | 仕様の最終 cross-check、`bootstrap.sh` 実行、初期 issue / task ファイル生成（レーン割当含む） |

bootstrap 完了後、**現在の Claude セッションを終了し `dev/` 内で再起動してください** — Claude Code にはセッション途中で作業ディレクトリを変更し `CLAUDE.md` / `settings.json` を再ロードする公式の手段がありません。生成される `start-dev.sh` ランチャーを使えばワンコマンドで切り替えられます:

```bash
# ステップ 1: 現在の Claude セッションを終了（Ctrl+D または /exit）
# ステップ 2: ターミナルで実行:
~/<project>/start-dev.sh   # <project>/dev/ をルートに claude を起動
# または同等: cd ~/<project>/dev && claude
```

新しいセッション内で:

```bash
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
| 1. Spec | 深掘り対話 + 機能 + データモデル | `/my-harness-init`（Discovery〜Features、データモデルはモックの後） |
| 2. Design | ロゴ + プラットフォーム別 UI モック + 仕様 iteration。モックがツール選定の入力になる | `/my-harness-init`（Visual → Tools フェーズ） |
| 3. Tasks | issue / task ファイル生成、4 レーンへのファイル所有割当、bootstrap 実行 | `/my-harness-init`（Bootstrap フェーズ） |
| 3.5. Switch session | `<root>/dev/` 内で Claude Code を再起動してプロジェクトスコープの CLAUDE.md と settings を読み込む | `<root>/start-dev.sh` |
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

## スラッシュコマンド

**直接使用する 2 つのスラッシュコマンド：**

- `/my-harness-init` — 新規プロジェクトをゼロから開始（プロジェクトごとに 1 回）。既存の `.my-harness/init-state.json` を検出すると保存済みフェーズから再開する。
- `/harness-team-lead` — 4 レーン並列実装の継続開発を調整する

この他に 19 個の規約 skill が文脈に応じて自動でロードされます（TDD / JSDoc / Hono Clean Architecture / Drizzle / Nix pure / デザイン規律 / 機密マスキング / Git 規律など）。ユーザーが直接呼ぶ必要はなく、エージェントがトピックに応じて読み込みます。

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
    ├── .claude/CLAUDE.md               常に生成されます。プロジェクト固有の規約はここに記述します。
    ├── dev/.claude/                    USE_GLOBAL_CLAUDE=no のときのみ生成（settings.json に claudeMdExcludes を書き込み ~/.claude/CLAUDE.md を除外）
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
LANG=en
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
USE_GITHUB_ISSUES=yes         # gh issue or "no"（ローカル docs/task/）
USE_GLOBAL_CLAUDE=yes         # "no" にすると dev/.claude/settings.json に claudeMdExcludes を書き込み ~/.claude/CLAUDE.md を除外
CODEX_SESSION=my-harness-init
USE_CODEX_ENGINEER=yes        # engineer subagent を Codex に委譲（USE_CODEX=yes のときのみ意味あり）
USE_CODEX_E2E_REVIEWER=no     # E2E レポート合成を Codex に委譲（デフォルト: no — Claude がローカルで実行）
USE_CODEX_REVIEWER=yes        # 規約レビューを Codex に委譲
ON_CODEX_AUTH_FAIL=pause      # 既定: 認証/サブスク切れ時にユーザー通知＋待機、re-login 後 resume。fail なら即失敗
PACKAGE_MANAGER=pnpm          # pnpm | bun | npm | yarn — install/exec 行・flake.nix・husky・CI に反映
ARCHITECTURE=client-server    # client-server | client-serverless | p2p-pure | p2p-hybrid
                              # p2p-pure はバックエンド bootstrap をスキップ、p2p-hybrid は軽量 coordinator のみ
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

**Q: 4 レーン並列って具体的にどう動く？**
A: `harness-team-lead` が issue を **ファイル所有が重ならない** ように `lane/1`〜`lane/4` に振り分け、各レーンが independent worktree で analyst → engineer → e2e-reviewer → reviewer を順に走らせます。詳細は [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)。

**Q: `dev/docs/talk/` に変なこと書いたらリポジトリに残る？**
A: 残ります（`mask-secrets.sh` で機密はマスクされますが、内容自体は git 管理対象）。private repo 推奨。「talk を git 管理したくない」場合は `dev/.gitignore` に `dev/docs/talk/` を追加してください（推奨方針からは外れます）。

**Q: このプロジェクトを個人の `~/.claude/CLAUDE.md` から隔離できますか？**

A: できます。Setup で `USE_GLOBAL_CLAUDE=no` を選択してください。プラグインが `dev/.claude/settings.json` に `claudeMdExcludes` としてあなたの `~/.claude/CLAUDE.md` の絶対パスを書き込みます。Claude Code はこれをネイティブに尊重し、`dev/` 配下で開始したセッションではグローバル指示がスキップされます。なお、マネージドポリシーの CLAUDE.md（組織デプロイの `/Library/Application Support/ClaudeCode/CLAUDE.md` など）は個別プロジェクトの設定では除外できません。

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

PR 歓迎。**プラグインを使うために `git clone` してはいけません** — インストールは `/plugin marketplace add <github-url>` で行い、更新は `/plugin marketplace update` で受け取る設計です。clone するとそのリビジョンに固定されて古くなり続けます。

変更を提案するには:

1. GitHub 上でこのリポジトリを Fork する。
2. Claude Code 内で自分の fork をローカルマーケットプレースとして登録: `/plugin marketplace add https://github.com/<自分のユーザー名>/my-harness-generator` → `/plugin install my-harness@my-harness-generator`。
3. fork 側を編集 → push → Claude Code で `/plugin marketplace update` を実行して動作確認。
4. このリポジトリへ PR を出す。

プラグイン自身のコードに適用される規約:

- shell スクリプトは `bash -n`（構文チェック）を通ること必須。
- 全 `SKILL.md` は frontmatter `name` + `description` 必須。
- コミットは Conventional Commits + 日本語本文。
- レーン規約は [`docs/WORKFLOW.md`](./docs/WORKFLOW.md) を参照。

## ライセンス

MIT — [`LICENSE`](./LICENSE) を参照。
