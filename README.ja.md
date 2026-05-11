# my-harness-generator（日本語版）

> 「何を作るかぼんやりしている」状態から、本番運用可能なフルスキャフォルディング済プロジェクトを 1 回の会話で立ち上げる Claude Code プラグイン。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-orange.svg)](https://code.claude.com)
[![English](https://img.shields.io/badge/lang-English-blue.svg)](./README.md)

[English version / 英語版はこちら](./README.md)

## 概要

構造化インタビューであなたから引き出し、必要なら Codex に第二意見を求め、画面ごとに「ページ + パーツ一覧」を 1 枚の画像で生成 (上にフルページモック、下に使われている UI 部品を 4 列グリッドで透過 PNG として一覧化、Claude が自動切り抜き + 実行時アセット + TSX コンポーネント化)、技術スタックを決定し、ブランチ保護・CI・hooks・セキュリティ middleware・runbook・並列レーンの規約までセットされた**プロダクション級**モノレポを 1 つのスラッシュコマンドから生成。最初のコミットは緑、`main`/`stage`/`dev` は保護済み、会話はマスク済みで `dev/docs/talk/` に自動記録。

## プロダクション級デフォルト (5.0+)

**そのまま本番に出せる**スキャフォールドを生成します。後から付けるのが大変なものを bootstrap 時に全部配線:

- **Hono middleware スイート** — セキュリティヘッダー (CSP/HSTS/COOP/CORP/Permissions-Policy)、KV ベースレート制限、構造化ログ (pino + `x-request-id`)、冪等性 (`Idempotency-Key`)、CORS 明示許可リスト
- **ヘルスエンドポイント** — `/healthz` / `/readyz` (DB ping + smoke) / `/livez`
- **可観測性 + サプライチェーン** — Sentry 初期化、監査ログヘルパー、フィーチャーフラグ (安定 hash で % rollout)、CodeQL、CycloneDX SBOM、ライセンス監査、k6 smoke、Lighthouse CI、Renovate、Dependabot
- **runbook 6 本** — `incident-response.md` / `deploy.md` / `rollback.md` / `dr-plan.md` / `oncall.md` / `postmortem.md` (5-whys ブレームレス)
- **ローンチ前チェックリスト** in `rules/production.md` — バックアップ復元ドリル、ZAP full scan、負荷試験、CSP 強制、カオスドリル、オンコールローテーション
- **OS 別 `MAX_LANES` 推奨** — macOS の memory compression と live `memory_pressure` を考慮 (16GB Mac green なら 4 レーン推奨、ランタイムゲートが安全網)

ファイル単位の対応は [`docs/PRODUCTION.md`](./docs/PRODUCTION.md) を参照。

## ハイライト

- **`/my-harness-init`** — インタビュー → 仕様書 → `bootstrap.sh` まで自動。任意で Codex CLI による session resume + `gpt-image-2` で画面ごとの「ページ + パーツ一覧」モック生成 (1 枚の画像に上半分フルページ・下半分は使用 UI 部品の透過 PNG グリッド)。
- **プラットフォームごとに独立してフレームワーク選択可能** — Web（`nextjs`/`tanstack`）、iOS（`swift`/`expo`/`flutter`）、Android（`kotlin`/`expo`/`flutter`）、Desktop（`tauri`/`electron` × macOS/Windows/Linux）、バックエンド（`hono`/`gin`/`rust`）、DB（`d1`/`postgres`/`mysql`/`sqlite`）。
- **並列レーン (Agent Teams)** — `/harness-team-lead` が最大 `MAX_LANES` (1..4) × 4 役を起動。レーンは 1 つずつ、RAM/swap/compressor ゲート通過時のみ追加。OS 別 MAX_LANES 推奨は macOS の memory compression と live `memory_pressure` を考慮。PR 後は対象レーンの 4 teammate に `/clear`。`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 必須。
- **自動機密マスキング** — `UserPromptSubmit` フックが `mask-secrets.sh`（9 パターン）を通して `dev/docs/talk/<日付>.md` に記録。
- **規約はツール横断で 1 セット** — `rules/*.md` を `dev/CLAUDE.md` + `dev/AGENTS.md` + `codex-ask.sh --context` で Claude / Codex / Cursor / Aider が同じ内容を読み込む。

プロダクションスタック (Hono middleware / runbook / CI / observability) の詳細は上記セクションと [`docs/PRODUCTION.md`](./docs/PRODUCTION.md) を参照。

## インストール

前提: Claude Code 最新版。さらに **(a)** Nix 推奨（`nix develop` / `direnv allow` で `codex` / `rtk` / `python+SDK` / `jq` / `bash` / `git` がそろう）、または **(b)** `git` / `bash` / `jq` / `direnv` / `python3.12+` に加え `codex`（`npm install -g @openai/codex`）と `rtk`（`brew install rtk`）を自分で導入。いずれにせよ最初に一度 `codex login`（ChatGPT サブスクリプション必須）。

Nix で新規マシンに導入:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
git clone https://github.com/kirinnokubinagai/my-harness-generator
cd my-harness-generator
direnv allow                 # または `nix develop`
codex login
```

対応 OS: macOS (arm64/x86_64)、Linux (x86_64/aarch64)、Windows は WSL2 経由。macOS arm64 の初回 `nix develop` は `codex` のソースビルドが発生する場合あり（~20–60 分）。以後は即起動。レーンの Codex 呼び出しは共有 `codex app-server` デーモン（`harness-codex-daemon` skill）でまとめて捌く。

Claude Code 内で:

```
/plugin marketplace add https://github.com/kirinnokubinagai/my-harness-generator
/plugin install my-harness@my-harness-generator
```

新しい skills と hooks を有効化するため Claude Code を完全再起動（または `/clear`）。`/my-harness-init` を実行して最初の質問が出ればインストール成功。中断は `Esc`。

## クイックスタート

`/my-harness-init` の最初の質問で英語 / 日本語を選択。それ以降に生成されるすべての内容がその選択に従います。1 ターン 1 問、Q&A はマスク済みで `dev/docs/spec/` と `dev/docs/talk/` に自動保存。順序は「深掘り → 構造 → 機能 → **モックを先に作ってからツール選定** → データモデル」。

| # | フェーズ | 決めること |
|---|---|---|
| 0 | Language | 以降のインタビューを英語 / 日本語のどちらで進めるか |
| 1 | Setup | プロジェクトルート、AI ヘルパー (Claude / Claude + Codex)、グローバル CLAUDE.md の扱い、タスク管理 (markdown / GitHub Issues)、`MAX_LANES` (1..4) |
| 2 | Discovery | 自由対話で深掘り — 失敗パターン・反対者・スケール限界・信頼根拠・差別化・運用 6 カ月後 |
| 3 | Structure | アーキテクチャ (client-server / serverless / pure P2P / hybrid P2P) + プラットフォーム複数選択 |
| 4 | Features | 全機能リスト → 機能ごとに「経路 / 失敗 / 観測 / オンボード / 上級者ショートカット / 空状態 / 失敗復旧 / レイテンシ予算」 |
| 5 | Visual | プラットフォーム別に画面ごとの「ページ + パーツ一覧」モック 3〜5 個 (`gpt-image-2`)、Claude が透過 PNG に切り抜き → `dev/public/design/parts/` + `parts.ts` + TSX コンポーネント生成、各モックを深掘り |
| 6 | Tools | フレームワーク / バックエンド / DB / パッケージマネージャー / メール / E2E / Claude Code Action — 承認済モックを参照しながら |
| 7 | Data model | エンティティ・関係・PII (mermaid ER)、各エンティティを「ライフサイクル / GDPR / 権限 / 規模実態 / マイグレーション」で深掘り |
| 8 | Bootstrap | 仕様の最終 cross-check、`bootstrap.sh` 実行、初期 issue / task 生成 |

bootstrap 完了後、**現セッションを終了し `dev/` 内で Claude を再起動** (mid-session で CLAUDE.md / settings を reload する公式手段なし):

```bash
# Ctrl+D または /exit、その後:
cd ~/<project>/dev && claude
direnv allow
nix develop --command pnpm install
nix develop --command pnpm exec husky
nix develop --command pnpm exec vitest run    # health.test.ts が緑

git remote add origin git@github.com:<owner>/<repo>.git
git push --all origin
bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>
```

## ライフサイクルと日常コマンド

| 段階 | 内容 | コマンド |
|---|---|---|
| Spec → Design → Tasks | インタビュー → モック → ツール選定 → bootstrap | `/my-harness-init` |
| Switch session | `<root>/dev/` で再起動して project-scope CLAUDE.md / settings をロード | `cd <root>/dev && claude` |
| Implementation | 並列レーン (ファイル所有で衝突回避) | `/harness-team-lead` |
| Deploy | 初回は Alchemy v2 infra + Secrets 生成、以降は dev → stage → main 段階的リリース (ZAP / Playwright / Maestro / canary 10% → 100%) | `/harness-deploy` |
| 既存 repo を harness 化 or plugin 更新後の同期 | 冪等。`.bare/` の有無で自動分岐 | `/my-harness-adopt` |
| ライブ観察 (別ターミナル) | | `bash <plugin>/scripts/monitor-agents.sh <project-root>` |
| Watchdog モード | lead が Step 3.0 で消費 | `bash <plugin>/scripts/monitor-agents.sh <project-root> --watchdog` |

hotfix は手動: `main` から `hotfix/<short>`、`main` へ PR、merge-commit で `stage`/`dev` に back-merge。詳細は `docs/HOTFIX.md`。

## 規約 (single source of truth: `rules/*.md`)

すべての harness 規約は `rules/*.md` に集約され、全エントリポイントが自動で読み込みます。bootstrap が `<root>/dev/.my-harness/rules/` にミラーし、`dev/CLAUDE.md` + `dev/AGENTS.md` に埋め込み (Claude / Codex / Cursor / Aider が native に読み込む)、`codex-ask.sh --role` が context に自動 attach。個別の規約 slash command はありません。

| rule ファイル | 内容 |
|---|---|
| `rules/tdd.md` | Red / Green / Refactor、AAA、`$LANG` テスト名 |
| `rules/hono-clean-arch.md` | 4 層 Clean Architecture、厳格な依存方向 |
| `rules/drizzle.md` | Drizzle migrate-only、`drizzle-kit push` 禁止 |
| `rules/nix-pure.md` | 全ツールを per-worktree devshell 経由、`brew install` 禁止 |
| `rules/design.md` | Lucide Icons のみ、AI 風グラデ禁止、WCAG AA |
| `rules/jsdoc.md` | 全 export に TSDoc、関数内インラインコメント禁止 |
| `rules/no-hardcoded-secrets.md` | env vars / SOPS のみ、pre-commit で gitleaks |

## スラッシュコマンド

- `/my-harness-init` — 空ディレクトリから新規プロジェクトを開始 (`.my-harness/init-state.json` で再開)。
- `/my-harness-adopt` — 冪等。初回 (`.bare/` 無し) は既存 git repo を harness 構造に変換 (履歴保持)。2 回目以降 (`.bare/` あり) は `dev/.my-harness/` を最新 plugin で refresh し `dev/CLAUDE.md` / `dev/AGENTS.md` を再生成。refresh パスは非破壊。
- `/harness-team-lead` — 並列レーン統括。
- `/harness-deploy` — 冪等。初回は setup、以降は段階的リリース。
- `/harness-codex-daemon` — 共有 `codex app-server` デーモンの start/stop。

## 生成されるレイアウト

```
<project>/
├── .bare/                              bare git
├── .git → .bare
├── .my-harness/.config                 選択した設定 (committed)
├── .my-harness/codex-sessions/         Codex session IDs (gitignored)
├── dev/   stage/   main/               worktree (dev で作業)
├── lanes/feat-<n>-<slug>/              feature worktree (≤ MAX_LANES)
└── lanes/hotfix-<n>-<slug>/            hotfix worktree
    ├── .claude/CLAUDE.md               プロジェクト規約
    ├── dev/.claude/                    USE_GLOBAL_CLAUDE=no のとき (claudeMdExcludes)
    ├── docs/{spec,design,talk,task}/   仕様 / モック / 会話ログ / タスク
    ├── .my-harness/                    plugin runtime (rsync)
    ├── flake.nix .envrc                Nix pure 環境
    ├── biome.json package.json         開発ツール
    ├── .husky/                         pre-commit / pre-push / commit-msg
    └── .github/workflows/              CI 9 本
```

## ブランチ規約

| from → to | 必要条件 |
|---|---|
| `feat/*` → `dev` | PR + format / lint / test / typecheck 全 green |
| `dev` → `stage` | 人間承認 + OWASP ZAP + Playwright + Maestro + Semgrep + Trivy 緑 |
| `stage` → `main` | 人間承認 + 全ゲート緑 + canary 10% → 100% |
| `hotfix/*` → `main` | 緊急承認 + 最小 test/lint/format (post-merge で ZAP/E2E 即時) |

`main` / `stage` への直接 push は pre-push フック + GitHub branch protection で二重遮断。protection は一度だけ `bash scripts/setup-branch-protection.sh <owner>/<repo>` で適用。

## 設定オプション

インタビューは `<root>/.my-harness/.config` を生成。非対話再実行は `bash bootstrap.sh <root> --config <root>/.my-harness/.config`。主なキー: `LANG`, `PROJECT_NAME`, プラットフォームごとの `USE_<X>`/`<X>_KIND`, `USE_BACKEND`/`BACKEND_KIND`, `USE_DB`/`DB_KIND`, `USE_EMAIL`, `USE_PLAYWRIGHT`, `USE_MAESTRO`, `USE_CLAUDE_ACTION`, `CLAUDE_AUTH`, `USE_GITHUB_ISSUES`, `USE_GLOBAL_CLAUDE`, 役割ごとの `USE_CODEX_*`, `ON_CODEX_AUTH_FAIL` (`pause`/`fail`), `PACKAGE_MANAGER`, `ARCHITECTURE`, `MAX_LANES` (1..4), `HARNESS_LANE_RAM_MB` / `HARNESS_LANE_SWAP_MAX_MB` / `HARNESS_LANE_COMP_MAX_MB` (per-lane gate しきい値)。

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| skill が発火しない | Claude Code を完全再起動 / `/clear` |
| hook が `dev/docs/talk/` に書かない | `~/.claude/settings.json` に plugin の `UserPromptSubmit` / `Stop` hook が登録されているか確認 → `/doctor` |
| Codex 認証エラー | `codex login` |
| `blocked-codex-auth` (実行中に login 切れ) | `codex login` → team-lead に「resume」。サーバー側で session 保持 |
| `subscription-or-quota` | ChatGPT サブスクを再有効化、または `.my-harness/.config` で `USE_CODEX_<ROLE>=no` → 「resume」 |
| hotfix 逆流コンフリクト | `git merge --no-ff` で手動解消 (rebase / reset --hard / push --force 禁止) |
| 誤って `drizzle-kit push` | revert → `drizzle-kit generate --name <具体名>` → `wrangler d1 migrations apply` |
| plugin 更新 | `/plugin marketplace update` → `/plugin install my-harness@my-harness-generator` |

## よくある質問

**Q: 既存プロジェクトに導入できる？** `/my-harness-adopt` を使ってください。`.bare/` が無い状態で初回実行すると、既存 repo を harness 構造に変換 (履歴は保持、worktree レイアウトは破壊的)。

**Q: Codex CLI 必須？** いいえ、任意。Setup で `n` を選べば Claude 単独で全フェーズ進行 (画像生成だけスキップ)。

**Q: 並列レーンって具体的に？** `harness-team-lead` がファイル所有が重ならないように issue をレーンに振り分け、各レーンが independent worktree で analyst → engineer → e2e-reviewer → reviewer を順に走らせます。詳細は [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)。

**Q: `dev/docs/talk/` はリポジトリに残る？** はい（private repo 推奨）。機密は `mask-secrets.sh` でマスクされますが内容自体は git 管理対象。コミットしたくない場合は `dev/.gitignore` に追加。

**Q: 個人 `~/.claude/CLAUDE.md` から隔離したい** Setup で `USE_GLOBAL_CLAUDE=no` を選択。`dev/.claude/settings.json` の `claudeMdExcludes` にあなたの絶対パスを書き込みます。マネージドポリシー CLAUDE.md (組織デプロイ) は個別プロジェクト設定では除外不可。

## 詳細ドキュメント

- プロダクションガイド: [`docs/PRODUCTION.md`](./docs/PRODUCTION.md)
- 作業フロー: [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)
- Hotfix 手順: [`docs/HOTFIX.md`](./docs/HOTFIX.md)
- セットアップ + セキュリティ: [`docs/SETUP.md`](./docs/SETUP.md)
- インフラ: [`docs/INFRA.md`](./docs/INFRA.md)
- iOS DAST: [`docs/IOS_DAST.md`](./docs/IOS_DAST.md)
- エンジニア規約: `rules/*.md` (`rules/production.md` 含む)

## 貢献

PR 歓迎。**プラグインを使うために `git clone` してはいけません** — インストールは `/plugin marketplace add <github-url>`、更新は `/plugin marketplace update` で受け取る設計です。貢献方法: fork → 自分の fork をローカルマーケットプレースとして追加 → 編集 / push → `/plugin marketplace update` で動作確認 → PR back。shell スクリプトは `bash -n` 必須、`SKILL.md` は front-matter `name` + `description` 必須、コミットは Conventional Commits + 日本語本文。

## ライセンス

MIT — [`LICENSE`](./LICENSE) を参照。
