# my-harness-generator（日本語版）

> 「何を作るかぼんやりしている」状態から、本番運用可能なフルスキャフォルディング済プロジェクトを 1 回の対話で立ち上げる Claude Code plugin。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-orange.svg)](https://code.claude.com)
[![English](https://img.shields.io/badge/lang-English-blue.svg)](./README.md)

[English version here](./README.md)

---

## このプラグインの存在意義

世にあるスターターキットは「ボイラープレート」をくれるが、**本当に難しい部分**（要件定義、アーキテクチャ選定、レーン割当、セキュリティ規律）はあなた任せ。  
このプラグインは Claude が **7 段階のインタビュー** であなたから引き出し、必要なら OpenAI Codex に第二意見を求め、ロゴを生成し、技術スタックを決定し、ブランチ保護・CI・hooks・4 レーン並列開発の規約までセットされた完全なモノレポを 1 つのスラッシュコマンドから生成する。

## 主な機能

- **`/my-harness-init`**: プロダクト要件 7 段階深掘りインタビュー → 仕様書 (markdown) → 自動 bootstrap
- **Codex CLI 連携（任意）**: session resume による真のマルチターン対話、ロゴ・OG 画像生成（gpt-image-2）
- **ワンコマンド bootstrap**: bare git + dev/stage/main worktree + Husky + Biome + Nix flake + GitHub Actions 9 本 + Hono + Drizzle + Resend + Playwright + Maestro
- **4 レーン並列開発**: analyst → engineer → e2e-reviewer → reviewer の役割で 4 issue を並行処理（agent 5 個）
- **自動機密マスキング**: `UserPromptSubmit` フックがユーザー入力を `mask-secrets.sh`（9 パターン）に通して `dev/docs/talk/<日付>.md` に記録
- **20 個の skill を lazy load**: TDD / Hono Clean Architecture / Drizzle migrate-only / Nix pure / デザイン規律 / JSDoc / Git 規律 / ハードコード機密検出 等
- **GitHub Issue モード切替（任意）**: `gh issue create` を使うか、ローカル `docs/task/*.md` ファイルで管理するか選べる

## インストール

### 前提条件

- Claude Code（最新版）
- `git` / `bash` / `jq` / `direnv`（Nix dev shell 自動切替用）
- （任意）Codex 連携を使うなら `npm install -g @openai/codex` + `codex login`

### Plugin インストール（2 行）

Claude Code で:
```
/plugin marketplace add https://github.com/kirinnokubinagai/my-harness-generator
/plugin install my-harness@my-harness-generator
```

その後、新しい skills と hooks を有効化するため **Claude Code を完全再起動**（または `/clear`）してください。

### 動作確認

```
/my-harness-generator
```
最上位 skill が反応し、利用可能なコマンドの一覧が表示されれば成功です。

## クイックスタート（5 分で初プロジェクト）

```
/my-harness-init
```

Claude が以下を 1 問ずつ訊いてきます:

1. **プロジェクトのルートディレクトリ**（既定: `~/<project-name>`）
2. **プロジェクト名**（slug、英小文字 + ハイフン）
3. **Codex 連携を使う？**（y/n）
4. （y の場合）Codex ログイン状態確認 + session 名
5. **タスク管理方式**（y = GitHub Issue、n = ローカル `docs/task/`）
6. **個人の Claude グローバル設定を引き継ぐ？**（y / n）

その後、7 段階のインタビューに入ります:

| 段階 | テーマ | 成果物 |
|------|--------|--------|
| 1 | 問題定義 | `dev/docs/spec/01-problem.md` |
| 2 | ペルソナ / ユーザー | `dev/docs/spec/02-personas.md` |
| 3 | 機能 / MVP 境界 | `dev/docs/spec/03-features.md` |
| 4 | 技術スタック | `dev/docs/spec/04-stack.md` + `.my-harness/.config` |
| 5 | データモデル | `dev/docs/spec/05-data-model.md`（mermaid ER 図含む） |
| 6 | ビジュアル / ブランド | `dev/docs/spec/06-visual.md` + `dev/docs/design/logo-*.png` |
| 7 | 仕様確定 + bootstrap | `bootstrap.sh --config .my-harness/.config` を非対話で起動 |

すべての Q&A は **`UserPromptSubmit` フック経由でマスク後に** `dev/docs/talk/<日付>.md` に自動記録されます。

bootstrap 完了後:

```bash
cd ~/<project-name>/dev
direnv allow                                       # Nix shell 自動切替
nix develop --command pnpm install
nix develop --command pnpm exec husky              # husky 9.x 初期化
nix develop --command pnpm exec vitest run         # health.test.ts が緑になればOK
```

GitHub に push:

```bash
git remote add origin git@github.com:<owner>/<repo>.git
git push --all origin                                       # main/stage/dev 一斉
bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>    # 必要 secrets だけ対話登録
```

## 詳細な使い方

### 1. feature 開発を始める（4 レーン並列）

```
/harness-new-feature 42 user-login
```

Claude が `harness-new-feature` skill を呼び、内部で `new-feature.sh 42 user-login` を実行 → `lanes/feat-42-user-login/` に dev 起点 worktree 作成。

```bash
cd lanes/feat-42-user-login
direnv allow
```

**TDD 必須**: `harness-tdd` skill が「テストを書く」「バグを直す」と言うと自動発火。先に失敗するテストを書く:

```ts
// src/auth/login.test.ts
import { describe, expect, it } from 'vitest';
import { login } from './login';

describe('login', () => {
  it('メールアドレスが空の場合エラーになること', async () => {
    const result = await login({ email: '', password: 'x' });
    expect(result.error).toBe('メールアドレスは必須です');
  });
});
```

赤を確認:
```bash
nix develop --command pnpm exec vitest related --run src/auth/login.test.ts
```

最小実装 → 緑 → リファクタ → JSDoc 追加（`harness-jsdoc` skill が指導）→ commit:

```bash
git add -A
git commit -m "feat(auth): メールアドレス必須バリデーションを追加"
# husky pre-commit が biome / vitest / tsc / gitleaks / forbidden-pattern を実行
git push origin feat/42-user-login
gh pr create --base dev --title "feat(#42): ユーザーログイン"
```

CI（`pr-to-dev.yml`）が quality / e2e / claude-review を実行 → 全 green で auto-merge。

### 2. Codex に第二意見を求める

skill 経由（推奨）:
```
/harness-codex-consult
```

または普通に話す:
> 「Codex に聞いてください、Hono の middleware 順序として A→B→C と B→A→C どちらが妥当ですか」

Claude が内部で:
```bash
codex-ask.sh --role architect "<質問本文>"
```
を呼び出し。session は `/my-harness-init` 段階 0 で `--set-active <root>` 済みなので **自動 resume**（Codex は前段階全部覚えている）。

### 3. ロゴ / 画像を生成する

`/my-harness-init` 段階 6 でも、後からでも:

> 「todo-app のロゴを 3 案、ミニマル / ベクター / 主色 #14b8a6 で `dev/docs/design/logo-{1,2,3}.png` に保存して」

Claude が `harness-codex-consult` を `role: designer` で呼び出し。Codex（gpt-image-2 アクセス可能）が生成・保存。**専用フラグ不要**、普通の対話文で頼むだけ。

### 4. Hotfix（本番障害の緊急修正）

```
/harness-new-hotfix 99 critical-auth-bypass
```

`lanes/hotfix-99-critical-auth-bypass/` を **main 起点**（dev でなく）で作成。修正 → push → main 向け PR → 緊急承認 → マージ:

- `post-merge-hotfix.yml` が OWASP ZAP / MobSF を即時実行
- main → stage → dev に **マージコミットで** 自動逆流（rebase 禁止）

### 5. コンフリクト解消

**`git rebase` / `git reset --hard` / `git push --force` は絶対禁止**。代わりに:

```
/harness-resolve-conflict
```

→ `resolve-conflict.sh` が `git merge --no-ff` のみで解消する手順をガイド。

### 6. hotfix 後に全 feature ブランチを同期

```
/harness-sync-features
```

→ `sync-features-with-dev.sh` が `lanes/feat-*` をすべて走査し、各 worktree で `git merge --no-ff origin/dev` を実行。

### 7. 機密チェック（手動）

```
/harness-check-secrets
```

→ `check-forbidden-patterns.sh` が指定ファイルを走査し、環境変数キー直書き / 本番 DSN / 平文 `.env` 等を検出。pre-commit でも自動実行されるが、commit 前に手動確認したいとき用。

### 8. ブランチ保護を一括適用（リポジトリ作成直後）

```
/harness-branch-protection
```

→ `setup-branch-protection.sh <owner>/<repo>` が main / stage / dev に保護ルールを適用:
- `allow_force_pushes=false`
- 必須レビュー（main=2 / stage=1 / dev=1）
- 必須 status checks（quality / e2e / security / claude-review）
- merge commit のみ許可（squash / rebase 禁止）
- auto-merge 有効化

## 提供される全 20 skills

### 最上位（2）
| skill | 発火タイミング |
|-------|--------------|
| `my-harness-generator` | 「ハーネスについて」「ハーネス更新」 |
| `my-harness-init` | 新規プロジェクトをゼロから |

### 規約系（10、lazy load）
| skill | 発火条件 |
|-------|---------|
| `harness-tdd` | テスト書く / バグ修正 / リファクタ |
| `harness-hono-clean-arch` | Hono ルート / サービス / リポジトリ実装 |
| `harness-drizzle-rules` | スキーマ変更 / マイグレーション |
| `harness-nix-pure` | コマンド実行 / ツールインストール |
| `harness-design-rules` | UI コンポーネント / 配色 / アイコン |
| `harness-jsdoc` | 関数 / 型 / コメント |
| `harness-git-discipline` | git 操作 / コンフリクト |
| `harness-no-hardcoded-secrets` | 環境変数 / API キー / `.env` |
| `harness-mask` | 手動マスキング |
| `harness-codex-consult` | 「Codex に聞いて」第二意見 |

### shell ラッパー（8）
| skill | ラップする shell | 用途 |
|-------|------------------|------|
| `harness-new-feature` | `new-feature.sh` | dev 起点 worktree 作成 |
| `harness-new-hotfix` | `new-hotfix.sh` | main 起点 hotfix worktree |
| `harness-resolve-conflict` | `resolve-conflict.sh` | マージコミットでコンフリクト解消 |
| `harness-sync-features` | `sync-features-with-dev.sh` | 全 feature を dev 同期 |
| `harness-check-codex-auth` | `check-codex-auth.sh` | Codex ログイン状態判定 |
| `harness-check-secrets` | `check-forbidden-patterns.sh` | 機密チェック |
| `harness-setup-secrets` | `setup-secrets.sh` | GitHub secrets 対話登録 |
| `harness-branch-protection` | `setup-branch-protection.sh` | 保護ルール一括適用 |

## アーキテクチャ図

```
[ユーザー入力]
    ↓
[UserPromptSubmit hook] → mask-secrets.sh → dev/docs/talk/<日付>.md
    ↓
[Claude]
    ↓ 必要に応じて lazy load
[harness-* skill]（20 個から自動選択）
    ↓ skill が指示
[shell スクリプト]
    ↓
[実装]
    ↓
[Stop hook] → assistant 応答抽出 → マスク → talk/ 追記
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
├── lanes/feat-<n>-<slug>/              feature worktree（4 レーン並列）
├── lanes/hotfix-<n>-<slug>/            hotfix worktree（main 起点）
└── dev/                                通常の作業 worktree
    ├── .claude/                        USE_GLOBAL_CLAUDE=no の場合のみ
    ├── docs/
    │   ├── spec/01-problem.md ...      仕様書（マスク済）
    │   ├── design/logo-*.png ...       生成画像
    │   ├── talk/<日付>.md               Q&A 全文ログ（マスク済）
    │   └── task/                       USE_GITHUB_ISSUES=no のときのタスク
    ├── .my-harness/                    plugin 本体のコピー
    ├── flake.nix .envrc                Nix pure 環境
    ├── biome.json package.json         開発ツール設定
    ├── .husky/                         pre-commit / pre-push / commit-msg
    └── .github/
        ├── workflows/                  CI 9 本（quality / e2e / security / scheduled）
        └── scripts/maybe-create-issue.js  USE_GITHUB_ISSUES 分岐ヘルパー
```

## ブランチ規約

| from → to | 必要条件 |
|-----------|---------|
| `feat/*` → `dev` | PR + format / lint / test / typecheck 全 green |
| `dev` → `stage` | 人間承認 + OWASP ZAP + Playwright + Maestro + Semgrep + Trivy 緑 |
| `stage` → `main` | 人間承認 + 全ゲート緑 + canary 10% → 100% |
| `hotfix/*` → `main` | 緊急承認 + 最小 test/lint/format（post-merge で ZAP/E2E 即時） |

`main` / `stage` への直接 push は pre-push フック + GitHub branch protection で **二重に遮断**。

## 強制される規約（skill が自動指導）

- **TDD 厳格**: Red-Green-Refactor。テスト無しで本番コード書いたら削除して書き直し
- **Hono Clean Architecture**: domain ← application ← infrastructure / interfaces、依存方向厳守
- **Drizzle migrate のみ**: `drizzle-kit push` 禁止（履歴・ロールバック不可のため）
- **Nix pure**: 全ツール実行は `nix develop --command` 経由、`brew install` 禁止
- **AI 風デザイン禁止**: Lucide Icons のみ、グラデ / ネオン / 絵文字禁止、WCAG AA、UX 心理学 47 原則の主要 10
- **JSDoc / TSDoc 必須**、関数内コメント禁止、説明はすべて日本語
- **Git**: `rebase` / `reset --hard` / `push --force` 禁止、コンフリクトはマージコミット

## 設定オプション

`/my-harness-init` のインタビュー結果は `<root>/.my-harness/.config` に保存:

```bash
PROJECT_NAME=todo-app
USE_WEB=yes                # Web フロントエンド + バックエンド
USE_IOS=no                 # iOS Swift / SwiftUI
USE_ANDROID=no             # Android Kotlin / Jetpack Compose
USE_DB=yes
DB_KIND=d1                 # Cloudflare D1
USE_EMAIL=yes              # Resend + パスワードリセットフロー
USE_PLAYWRIGHT=yes         # Web E2E
USE_MAESTRO=no             # Mobile E2E
USE_CLAUDE_ACTION=yes      # PR レビューに Claude Code Action
CLAUDE_AUTH=oauth          # サブスクリプション or "api"（API キー）
USE_GLOBAL_CLAUDE=yes      # ~/.claude/CLAUDE.md を引き継ぐ or プロジェクト独立
USE_GITHUB_ISSUES=yes      # gh issue or "no"（ローカル docs/task/）
CODEX_SESSION=my-harness-init
```

非対話で再実行:
```bash
bash bootstrap.sh <root> --config <root>/.my-harness/.config
```

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| skill が発火しない | Claude Code を完全再起動 / `/clear` |
| hook が talk/ に書かない | `~/.claude/settings.json` に plugin の hooks エントリがあるか確認 |
| Codex 認証エラー | `/harness-check-codex-auth` → `codex login` |
| hotfix 逆流でコンフリクト | `/harness-resolve-conflict` を使う（rebase 禁止） |
| 誤って `drizzle-kit push` してしまった | revert → `drizzle-kit generate --name <具体名>` → `wrangler d1 migrations apply` |
| plugin を更新したい | `/plugin marketplace update` → `/plugin install my-harness@my-harness-generator` |
| dev で worktree 残骸 | `git worktree prune` で掃除（bootstrap が自動でやる） |
| `direnv: error Path 'flake.nix' is not tracked by Git` | `git add flake.nix && git commit`（bootstrap は自動でやる） |

## よくある質問

**Q: 既存プロジェクトに後から導入できる？**  
A: できますが推奨しません。`/my-harness-init` は新規前提。既存に当てたい場合は手動で `.my-harness/.config` を書いて `bootstrap.sh --config` を呼べば動きますが、bare git の付け替えなど破壊的変更が伴います。

**Q: Codex CLI 必須？**  
A: いいえ、任意です。`/my-harness-init` 段階 0 で n を選べば Claude 単独で全 7 段階進みます（画像生成だけスキップ）。

**Q: チームで使うとき個人差が出ない？**  
A: `USE_GLOBAL_CLAUDE=no` を選ぶと `dev/.claude/CLAUDE.md` にハーネス専用指示が配置され、個人の `~/.claude/CLAUDE.md` の影響を最小化できます（Claude Code 仕様上 100% isolate は不可）。

**Q: 4 レーン並列って具体的にどう動く？**  
A: `harness-team-lead` agent が GitHub issue を analyst-1〜4 / engineer-1〜4 / e2e-reviewer-1〜4 / reviewer-1〜4 の 4 レーンに振り分け、各 lane が independent worktree で並列に PR を作ります。詳細は [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)。

**Q: `docs/talk/` に変なこと書いたらリポジトリに残る？**  
A: 残ります（`mask-secrets.sh` で機密はマスクされますが、内容自体は git 管理対象）。private repo 推奨。「talk を git 管理したくない」場合は `dev/.gitignore` に `docs/talk/` を追加してください（推奨方針からは外れます）。

**Q: ハーネス自体を更新したい**  
A: `cd ~/.claude/plugins/cache/.../my-harness && git pull` ではなく、Claude Code の `/plugin marketplace update` → `/plugin install my-harness@my-harness-generator` を使う。

## 詳細ドキュメント

- 作業フロー: [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)
- Hotfix 手順: [`docs/HOTFIX.md`](./docs/HOTFIX.md)
- セキュリティ: [`docs/SECURITY.md`](./docs/SECURITY.md)
- インフラ: [`docs/INFRA.md`](./docs/INFRA.md)
- iOS DAST: [`docs/IOS_DAST.md`](./docs/IOS_DAST.md)
- エンジニア規約: [`docs/ENGINEER_STANDARDS.md`](./docs/ENGINEER_STANDARDS.md)
- セットアップ詳細: [`docs/SETUP.md`](./docs/SETUP.md)

## 開発（plugin 自体に貢献）

```bash
git clone https://github.com/kirinnokubinagai/my-harness-generator
cd my-harness-generator
# ローカルマーケットプレースとして追加して動作確認
/plugin marketplace add ./
/plugin install my-harness@my-harness-generator
```

PR 歓迎。Plugin は自分自身の規約を自分の開発にも適用しています:
- shell スクリプトは `bash -n` で構文 OK 必須
- SKILL.md は frontmatter `name` + `description` 必須
- コミットは Conventional Commits + 日本語本文
- レーン規約は [`docs/WORKFLOW.md`](./docs/WORKFLOW.md) 参照

## License

MIT（[LICENSE](./LICENSE) 参照）

---

## プロジェクト 6 段階ライフサイクル

このプラグインが強制する開発フロー全体:

| 段階 | 内容 | やり方 |
|------|------|--------|
| 1 | **仕様作成**（問題 / ペルソナ / 機能 / 技術スタック / データモデル） | `/my-harness-init` 段階 1–5 |
| 2 | **デザインモック + ロゴ + 仕様 iteration** | `/my-harness-init` 段階 6 — 主要画面 3–5 個の UI モックを Codex（gpt-image-2）で生成、モックを見て要件が変わったら段階 1–5 にループバック |
| 3 | **issue / task 作成** | `/my-harness-init` 段階 7 — `gh issue create`（USE_GITHUB_ISSUES=yes）またはローカル `dev/docs/task/{parent,child}/*.md`（=no） |
| 4 | **チーム実装 + close** | `/harness-new-feature <issue>` で feature worktree、`harness-team-lead` agent が 4 レーン並列に振り分け。PR マージで issue close |
| 5 | **デプロイ設定（Terraform）** | `/harness-deploy-setup` — `infra/main.tf`（Cloudflare provider）/ wrangler binding / GitHub secrets・vars / fastlane（iOS）を生成 |
| 6 | **デプロイ実行** | `/harness-deploy-execute` — dev → stage（自動 + 人間ラベル）→ main（canary 10% → 100%） |

### Fresh-agent-per-issue 原則

各 issue は **完全に新規の subagent context** で処理される。`harness-team-lead` は engineer / analyst / e2e-reviewer / reviewer を **必ず `Task(subagent_type=..., prompt=...)` で起動**し、`SendMessage` で前回の subagent を継続呼び出ししない。これにより:
- 前 issue の判断が現 issue に染み込まないのを保証
- context 累積によるトークンコスト増を抑制
- 各レーンが真に独立して動く

team-lead 自身の context が重くなったら（issue 5–10 個ごと）、進捗を `.my-harness/team-state.json` に保存してユーザーに「`/clear` してから team-state.json を読み直して再開してください」と案内する。
