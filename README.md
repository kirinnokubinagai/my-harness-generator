# my-harness-generator

> 汎用ハーネスジェネレータ Claude Code plugin。**`/my-harness-init`** で深掘りインタビュー → 仕様書生成 → bootstrap を一気通貫。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-orange.svg)](https://code.claude.com)

## 何ができる

- **対話で仕様を確定**: Claude が 7 段階の深掘り質問でプロダクト要件を引き出す
- **Codex 連携（任意）**: 重要分岐で第二意見、ロゴ・OG 画像生成も
- **ワンコマンド bootstrap**: bare git + dev/stage/main worktree + Husky + Biome + Nix flake + GitHub Actions + Hono + Drizzle + Resend + Playwright + Maestro
- **4 レーン並列開発**: analyst → engineer → e2e-reviewer → reviewer の役割で 4 issue 並行
- **機密マスキング**: ユーザー入力を hook で自動マスク → docs/talk に記録（9 パターン: API キー / AWS / メール / 電話 / カード / JWT / PEM / URL認証 / `KEY=value` 形式）
- **TDD 強制 / Git 規律 / Hono Clean Arch / Drizzle migrate のみ / Nix pure** 等を skills で lazy load

## インストール（Claude Code に）

### 1. マーケットプレース追加
```
/plugin marketplace add https://github.com/kirinnokubinagai/my-harness-generator
```

### 2. プラグインインストール
```
/plugin install my-harness@my-harness-generator
```

### 3. Claude Code を完全再起動
skills と hooks を有効化するため、Claude Code を再起動するか `/clear` を実行。

### 4. 動作確認
```
/my-harness-generator
```
最上位 skill が反応します。

## 最初の使い方

```
/my-harness-init
```

7 段階の対話インタビューが始まり、最後に bootstrap が走って完全なプロジェクトが立ち上がります。

## オプション: Codex CLI 連携

```bash
npm install -g @openai/codex
codex login
```

`/my-harness-init` 段階 0 で「Codex 連携を使う」を `y` にすると、各段階で Codex に第二意見を求められます。

## 提供される skills

### 最上位（2）
| skill | 説明 |
|-------|------|
| `my-harness-generator` | 全体ハブ skill |
| `my-harness-init` | 7 段階インタビュー → bootstrap |

### 規約（10、lazy load）
| skill | 発火条件 |
|-------|---------|
| `harness-tdd` | テスト / バグ修正 / リファクタ |
| `harness-hono-clean-arch` | Hono / API 実装 |
| `harness-drizzle-rules` | DB スキーマ変更 |
| `harness-nix-pure` | コマンド実行 / 環境構築 |
| `harness-design-rules` | UI / コンポーネント / 配色 |
| `harness-jsdoc` | 関数 / 型 / コメント |
| `harness-git-discipline` | git / コンフリクト |
| `harness-no-hardcoded-secrets` | 環境変数 / 機密 |
| `harness-mask` | 機密マスキング（明示的） |
| `harness-codex-consult` | Codex 第二意見・画像生成 |

### shell ラッパー（8）
| skill | ラップする shell |
|-------|------------------|
| `harness-new-feature` | `new-feature.sh` |
| `harness-new-hotfix` | `new-hotfix.sh` |
| `harness-resolve-conflict` | `resolve-conflict.sh` |
| `harness-sync-features` | `sync-features-with-dev.sh` |
| `harness-check-codex-auth` | `check-codex-auth.sh` |
| `harness-check-secrets` | `check-forbidden-patterns.sh` |
| `harness-setup-secrets` | `setup-secrets.sh` |
| `harness-branch-protection` | `setup-branch-protection.sh` |

## アーキテクチャ

```
[ユーザー入力]
    ↓
[UserPromptSubmit hook] → mask-secrets.sh → dev/docs/talk/<日付>.md
    ↓
[Claude]
    ↓ 必要に応じて lazy load
[harness-* skill] (20 種から自動選択)
    ↓ skill が指示
[shell スクリプト]
    ↓
[実装]
    ↓
[Stop hook] → 応答抽出 → マスク → talk/ 追記
    ↓
[git pre-commit] → gitleaks + check-forbidden-patterns で二重防御
    ↓
[push]
```

## 生成されるプロジェクト構造

```
<project>/
├── .bare/                              ベアリポ
├── .git → .bare                        git ファイル
├── .my-harness/.config                 設定（team-shared）
├── .my-harness/codex-sessions/         Codex session ID（gitignore）
├── dev/   stage/   main/               worktree（dev で作業）
├── lanes/feat-<n>-<slug>/              feature worktree（4 レーン並列）
└── dev/                                通常の作業 worktree
    ├── .claude/                        USE_GLOBAL_CLAUDE=no で独立配置
    ├── docs/{spec,design,talk,task}/   会話 / 仕様 / モック / タスク
    ├── .my-harness/                    ハーネス本体のコピー
    ├── flake.nix .envrc                Nix pure 環境
    ├── biome.json package.json         開発設定
    ├── .husky/                         pre-commit / pre-push / commit-msg
    └── .github/workflows/              CI 9 本（quality / e2e / security / scheduled）
```

## ワークフロー

### ブランチ規約
| from → to | 許可条件 |
|-----------|----------|
| `feat/*` → `dev` | PR + format/lint/test/typecheck 合格 |
| `dev` → `stage` | 人間承認 + OWASP ZAP + Playwright + Maestro + Semgrep + Trivy 合格 |
| `stage` → `main` | 人間承認 + 全ゲート緑 + canary |
| `hotfix/*` → `main` | 緊急承認 + 最小 test/lint/format（その後 stage / dev に逆流） |

### 4 レーン並列
team-lead が GitHub issue を 4 レーンに振り分け、各レーンで:
```
analyst-N → engineer-N（TDD 実装）→ e2e-reviewer-N → reviewer-N
                ↑                                       ↓
                └────── 修正フィードバック ─────────────┘
```

### 必須遵守事項（skills が強制）
- **TDD**: テスト先行、Red-Green-Refactor
- **Hono Clean Arch**: domain → application → infrastructure / interfaces
- **Drizzle のみ + `drizzle-kit migrate`**（`push` 禁止）
- **Nix pure**: `direnv allow` で自動、impure 禁止
- **AI 風デザイン禁止**: Lucide Icons のみ、グラデ・ネオン・絵文字禁止
- **JSDoc / TSDoc 必須**、関数内コメント禁止、説明はすべて日本語
- **Git**: `rebase` / `reset --hard` / `push --force` 禁止、コンフリクトはマージコミット

## 詳細ドキュメント

- 作業フロー: [`docs/WORKFLOW.md`](./docs/WORKFLOW.md)
- Hotfix: [`docs/HOTFIX.md`](./docs/HOTFIX.md)
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

## License

MIT (see [LICENSE](./LICENSE))
