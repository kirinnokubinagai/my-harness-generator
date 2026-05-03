---
name: my-harness-generator
description: ハーネスジェネレータ全体の最上位 skill。新規プロジェクト立ち上げ（/my-harness-init を発火）、ジェネレータの再インストール、harness-* skills 一覧の確認など、ハーネス全体に関する操作のハブ。「ハーネスについて」「ハーネス更新」「skills を再インストール」「新規プロジェクト」等の文脈で発火。
---

# /my-harness-generator

`my-harness-generator` ハーネス全体の **最上位 skill**。プロジェクト立ち上げ・更新・skills 一覧の確認をここから案内する。

## ハーネスの全体像

```
~/my-harness-generator/                 ジェネレータ本体（git 管理推奨）
├── scripts/                             21 本の shell（bootstrap / codex-ask / mask / ...）
├── templates/
│   ├── skills/harness-*/SKILL.md       18 個の規約 + shell ラッパー skill
│   ├── hooks/{log-user-prompt,log-claude-output}.sh   2 hook
│   ├── claude/{CLAUDE.thin.md, settings.template.json}
│   ├── github/workflows/*.yml          CI 9 本
│   ├── biome/biome.json
│   ├── nix/{flake.nix,.envrc}
│   ├── web/, db/d1/, email/resend/, android/, ios/
│   └── ...
└── docs/                                作業フロー / SECURITY / INFRA / IOS_DAST 等

~/.claude/                              Claude Code が読む場所
├── skills/
│   ├── my-harness-generator/SKILL.md   ← これ（top-level）
│   ├── my-harness-init/SKILL.md        ← /my-harness-init オーケストレータ
│   └── harness-*/SKILL.md (18)         ← 規約 + shell ラッパー
├── settings.json                       ← UserPromptSubmit/Stop hook 登録
└── agents/harness-*.md (5)             ← 4 レーン並列用 agent

<project>/                              生成プロジェクト
├── .my-harness/.config                 設定（team-shared）
├── .my-harness/codex-sessions/         Codex session ID（gitignore）
├── .bare/  dev/  stage/  main/  lanes/
└── dev/                                通常の作業 worktree
    ├── .claude/                        USE_GLOBAL_CLAUDE=no のとき独立配置
    ├── docs/{spec,design,talk,task}/   会話 / 仕様 / モック / タスク
    └── .my-harness/                    ハーネスのコピー（プロジェクト内で実行可能）
```

## できること（ユーザーがこの skill を呼ぶ動機）

### 1. 新規プロジェクトを始める
→ `/my-harness-init` を呼ぶよう案内（深掘りインタビュー → 仕様 → 自動 bootstrap）

### 2. harness-* skills と hooks をグローバル install / 更新
```bash
bash ~/my-harness-generator/scripts/install-skills-globally.sh
```
ジェネレータを更新（`git pull`）したあとに実行すると、~/.claude/skills/ が最新に同期される。

### 3. 既存プロジェクトに対して bootstrap を回す
```bash
bash ~/my-harness-generator/scripts/bootstrap.sh /path/to/project          # 対話
bash ~/my-harness-generator/scripts/bootstrap.sh /path/to/project --config <file>  # 非対話
```

### 4. 利用可能な skills 一覧

**規約系（10）**:
- `harness-tdd` / `harness-hono-clean-arch` / `harness-drizzle-rules`
- `harness-nix-pure` / `harness-design-rules` / `harness-jsdoc`
- `harness-git-discipline` / `harness-no-hardcoded-secrets`
- `harness-mask` / `harness-codex-consult`

**shell ラッパー（8）**:
- `harness-new-feature` / `harness-new-hotfix`
- `harness-resolve-conflict` / `harness-sync-features`
- `harness-check-codex-auth` / `harness-check-secrets`
- `harness-setup-secrets` / `harness-branch-protection`

### 5. ハーネスの設計思想を確認
- skills 中心: 詳細ルールは個別 skill に分割、CLAUDE.md は薄い振り分け表のみ
- shell は skill 経由で呼ぶ（Claude が引数を覚えなくて良い）
- hooks で機械的に保証（ユーザー入力の自動 talk 記録 + マスク）
- pre-commit が機密検出の最後の砦

## 関連 skill

- 新規プロジェクト立ち上げ: `my-harness-init`
- 規約・shell ラッパー: `harness-*`（上記 18）

## トラブル時

- skill が発火しない → Claude Code を再起動 or `/clear`
- hook が動かない → `~/.claude/settings.json` の hooks セクション確認
- Codex が反応しない → `harness-check-codex-auth` で診断
- ジェネレータを更新したい → `cd ~/my-harness-generator && git pull && bash scripts/install-skills-globally.sh`
