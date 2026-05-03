---
name: my-harness-init
description: プロダクト要件の深掘りインタビュー → 仕様書生成 → ハーネス自動構築までを一気通貫で行う。Claude が 7 段階の深掘り質問を進め、要所で Codex（architect / critic / analyst / planner / designer 等）に第二意見を求め、必要ならロゴや UI モックを Codex 経由で gpt-image-2 生成し、最後に my-harness-generator/scripts/bootstrap.sh を非対話モードで実行してプロジェクトを起動する。
---

# /my-harness-init

ユーザーが「何を作るか曖昧」な状態から、要件・技術スタック・データモデル・ビジュアルまでを **対話で確定** し、その仕様で **そのままハーネスを構築** するスラッシュコマンド。

## このスキルの実行主体

このスキルは **Claude（あなた）** が実行する手順書。Codex は外部の補助 LLM として、**Claude が Bash で `codex-ask.sh` を起動して** 質問を投げ、回答を読み取って取り込む形で連携する。Codex は Claude の代わりにユーザーと直接対話しない。

```
[ユーザー] ─── 対話 ───→ [Claude] ──Bash──→ codex-ask.sh ──exec──→ [Codex CLI]
                          ↑                                         │
                          └─────────── 回答（テキスト）───────────────┘
```

## 必須前提

- `~/my-harness-generator/scripts/bootstrap.sh` が存在する
- `~/my-harness-generator/scripts/codex-ask.sh` と `check-codex-auth.sh` が存在し、実行権限がある（Codex 連携時に使用）

## 永続成果物の配置（プロジェクトルート配下）

| ディレクトリ | 用途 | git 管理 |
|--------------|------|----------|
| `<root>/dev/docs/spec/` | 仕様書（段階ごとに分けて保存） | あり |
| `<root>/dev/docs/design/` | ロゴ・OG 画像・モックアップ | あり |
| `<root>/dev/docs/talk/` | ユーザーとの会話の全文ログ（マスク済） | あり |
| `<root>/dev/docs/task/` | タスク（USE_GITHUB_ISSUES=no のとき） | あり |
| `<root>/.my-harness/` | 内部作業領域（codex session id 等、機密扱い） | `.gitignore` 除外 |

## 機密マスキング（厳守）

ユーザーとの会話に **以下が含まれていたら、ファイル書き出し前に必ずマスク** する:

| 種類 | マスク後 |
|------|----------|
| API キー / トークン（`sk-...`, `sk-ant-...`, `ghp_...`, `xoxb-...` 等） | `<MASKED:api-key>` |
| AWS アクセスキー（`AKIA...`） | `<MASKED:aws-key>` |
| パスワード | `<MASKED:password>` |
| メールアドレス（個人特定可能なもの） | `<MASKED:email>` |
| URL に埋め込まれた認証情報（`https://user:pass@...`） | `<MASKED:url-cred>` |
| 電話番号 | `<MASKED:phone>` |
| クレジットカード番号 | `<MASKED:cc>` |
| PEM 形式秘密鍵 | `<MASKED:private-key>` |
| JWT 三段ドット文字列 | `<MASKED:jwt>` |

マスク対象は `docs/talk/` と `docs/spec/` への **書き込み前** に適用する。  
ユーザーの画面には素の内容が見えていても、ファイルにはマスク後を保存。  
判断に迷うときはユーザーに確認してから保存する。  
git の pre-commit でも `gitleaks` + `check-forbidden-patterns.sh` が二重に弾く（漏れ防止）。

## 7 段階フロー

各段階で:
1. ユーザーに質問（短く、1 ターン 1 問）
2. 回答を **マスク後** で `docs/spec/<stage>.md` に追記
3. Q&A 全文を **マスク後** で `docs/talk/<stage>.md` に追記
4. USE_CODEX=yes のとき Codex consult を流す
5. 段階の終わりに要約を表示し「次へ進む？」を確認

### 段階 0: 起動 + 各種選択

ユーザーに **以下を 1 問ずつ** 確認する:

1. プロジェクトのルートディレクトリ（既定: `~/<project-name>`）
2. プロジェクト名（slug、英小文字とハイフン）
3. **Codex 連携を使う？（y / n）**
   - y: 各段階で Codex に第二意見、段階 6 で画像生成も使える
   - n: Claude 単独で進める
4. y のとき: **Codex のログイン状態を確認**:
   ```bash
   bash ~/my-harness-generator/scripts/check-codex-auth.sh
   ```
   - `not-installed` → ユーザーに `npm i -g @openai/codex` を案内、ユーザー判断で y/n 再選択
   - `not-logged-in` → ユーザーに `codex login` を実行してもらう。再チェック。3 回失敗で自動 n に倒す
   - `logged-in` → 続行
5. y のとき: session 名（既定: `my-harness-init`）
6. **タスク管理方式（y = GitHub Issue 駆動 / n = ローカル `docs/task/`）**
7. **Claude グローバル設定の引き継ぎ（y / n）**

回答を 2 箇所に保存:

```bash
mkdir -p <root>/.my-harness <root>/dev/docs/spec <root>/dev/docs/design <root>/dev/docs/talk <root>/dev/docs/task

cat > <root>/.my-harness/.config <<EOF
PROJECT_NAME=<slug>
ROOT=<root>
USE_CODEX=<yes|no>
CODEX_SESSION=<session 名>          # USE_CODEX=yes のときのみ
USE_GITHUB_ISSUES=<yes|no>
USE_GLOBAL_CLAUDE=<yes|no>
EOF

cat > <root>/.my-harness/answers.txt <<EOF
<slug>
<web y/n>
<ios y/n>
<android y/n>
<db y/n>
<d1 or none>
<email y/n>
<playwright y/n>
<maestro y/n>
<claude y/n>
<api/oauth>
<global y/n>
<github_issues y/n>
EOF
```

USE_CODEX=yes のとき active session pointer を登録:

```bash
~/my-harness-generator/scripts/codex-ask.sh --set-active <root>
```

### 段階 1: 問題発見

聞くこと:
- 誰のどんな課題を解くか
- 既存サービスではダメな理由
- 利用シーン
- 5 年後の成功状態

各 Q&A 終わりに:

```bash
# spec（マスク済要件）
cat >> <root>/dev/docs/spec/01-problem.md <<EOF
- ユーザー: <マスク済の確定内容>
- 課題: ...
EOF

# talk（マスク済 Q&A 全文）
cat >> <root>/dev/docs/talk/01-problem.md <<EOF
## Q: 誰のどんな課題を？
A: <マスク済>
EOF
```

USE_CODEX=yes のとき Codex consult:

```bash
~/my-harness-generator/scripts/codex-ask.sh \
  --role critic \
  --out <root>/.my-harness/codex-stage1.md \
  --log <root>/.my-harness/codex.jsonl \
  "問題定義: <内容>。前提に矛盾がないか、対立する仮説を 3 つ挙げて批判してください。"
```

回答ファイルを Read で読み、ユーザーに要点を提示。

### 段階 2: ユーザー / ペルソナ

聞くこと: ユーザータイプ数、各タイプの利用シーン、技術リテラシ。  
保存先: `docs/spec/02-personas.md` / `docs/talk/02-personas.md`  
Codex consult: `--role analyst`

### 段階 3: 機能 / MVP 境界

聞くこと: 必須機能 5〜10 個、優先順位、MVP 境界。  
保存先: `docs/spec/03-features.md` / `docs/talk/03-features.md`  
Codex consult: `--role planner`

### 段階 4: 技術スタック決定

ハーネスが受け付ける選択肢にマップ:
- プラットフォーム: Web / iOS / Android（複数可）
- DB: D1 / なし
- メール: Resend / なし
- E2E: Playwright / Maestro
- Claude Code Action: 有無、認証は api / oauth

Claude が段階 1〜3 から **論理的に推奨** し、ユーザー承認を取る。  
保存先: `docs/spec/04-stack.md` / `docs/talk/04-stack.md` + `<root>/.my-harness/answers.txt` 更新  
Codex consult: `--role architect`

### 段階 5: データモデル（DB ありのときのみ）

聞くこと: エンティティ 3〜7 個、関係、PII の扱い。  
保存先: `docs/spec/05-data-model.md`（mermaid ER 図含む）/ `docs/talk/05-data-model.md`  
Codex consult: `--role architect`

### 段階 6: デザイン（ロゴ + UI モック）+ 仕様 iteration

**重要**: ロゴだけでなく **主要画面の UI モックアップ** もここで作る。モックを見て要件が変わったら **段階 1〜5 に戻って仕様修正** する iteration を許容する。

#### 6.1 ブランド方向性

聞くこと（短く 1 ターン 1 問）:
- ブランドの世界観（3 形容詞、例: 信頼・温かい・実用的）
- 主色 + 副色（実物例があれば）
- ロゴの方向性（マーク / ワードマーク / コンビ）
- トーン（フォーマル / カジュアル / 楽しい）

#### 6.2 ロゴ生成（USE_CODEX=yes）

```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh \
  --role designer \
  --out <root>/.my-harness/codex-stage6-logo.md \
  "$PROJECT_NAME のロゴを 3 案、各 PNG として以下に保存してください。
スタイル: <ブランドキーワード>
主色: <主色>
ミニマル、ベクター調、白背景、テキスト無し
保存先:
- <root>/dev/docs/design/logo-1.png
- <root>/dev/docs/design/logo-2.png
- <root>/dev/docs/design/logo-3.png"
```

ユーザーが 1 案を選定 → 選定理由を `docs/spec/06-visual.md` に記録。

#### 6.3 UI モックアップ生成（主要画面ごと）

段階 3 の機能リストから **主要画面 3〜5 個を選定**（例: ログイン / ホーム / 詳細 / 編集 / 設定）。各画面について Codex にモックを依頼:

```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh \
  --role designer \
  --out <root>/.my-harness/codex-stage6-mock-<画面名>.md \
  "$PROJECT_NAME の <画面名> 画面のモックを 2 案作成してください。
ターゲット: <段階 2 で定めたペルソナ>
主機能: <この画面で行う操作>
ブランド: <主色><キーワード>、Lucide Icons のみ、AI 風デザイン禁止
解像度: 375x812（モバイル）か 1280x800（デスクトップ）

保存先:
- <root>/dev/docs/design/mock-<画面名>-1.png
- <root>/dev/docs/design/mock-<画面名>-2.png"
```

各画面 2 案 → ユーザーが選定。OG 画像 / favicon も同方式で生成。

#### 6.4 仕様 iteration（重要）

モックを見たユーザーが「あ、この画面ならこの機能も必要」「この画面構成だとペルソナ B には複雑すぎる」等に気付いた場合:

- **段階 1〜5 のどれかに戻って仕様修正**
- 修正対象の `docs/spec/0X-*.md` を更新
- 必要なら Codex に再 critic / analyst で確認
- 修正完了後、段階 6 のモックを更新（差分のみ再生成可）

このループは **2〜3 回まで** が目安。それ以上は次フェーズに進めない。

#### 6.5 段階 6 完了基準

- [ ] ロゴ採用案 1 個が `dev/docs/design/logo-final.png`（or symlink）として確定
- [ ] 主要画面 3〜5 個のモックが選定済
- [ ] OG 画像 / favicon も生成済
- [ ] iteration で仕様が変わったなら `docs/spec/*.md` も最新
- [ ] `docs/spec/06-visual.md` に: 採用ロゴ / 配色 / 採用モック一覧 / iteration 記録

USE_CODEX=no のときは `dev/docs/design/brand.md` にテキストで方針（配色・形・各画面のレイアウト方針）を文章で残す。後でユーザーが Figma 等で手作業でモックを作れる仕様書にする。

保存先: `docs/spec/06-visual.md` / `docs/talk/06-visual.md` / `docs/design/{logo-*,mock-*,og,favicon}.png`

### 段階 7: 仕様確定 + bootstrap + issue/task 生成

#### 7.1 仕様の最終 cross-check
1. `docs/spec/*.md` を Read で全部読み、概観をユーザーに提示し承認を得る。
2. USE_CODEX=yes のとき、Codex code-reviewer に最終 cross-check:
   ```bash
   ${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh --role code-reviewer \
     --context <root>/dev/docs/spec/*.md <root>/dev/docs/design/*.png -- \
     "仕様 / モック / 技術スタックの整合性、論理矛盾、機能漏れを指摘してください。"
   ```
3. 修正があれば段階 1〜6 に戻ってから再度ここに来る。

#### 7.2 bootstrap 実行（非対話）
```bash
bash ${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/bootstrap.sh "<root>" --config "<root>/.my-harness/.config"
```
bootstrap が dev worktree に scaffold を作り初期コミット → `docs/spec/`, `docs/design/`, `docs/talk/` も含まれて git 管理される。

#### 7.3 issue / task 生成（USE_GITHUB_ISSUES に応じ分岐）

機能リスト（段階 3）から **300 行以内の子 issue** に分割し、ファイル衝突防止のためファイル所有を宣言:

- **USE_GITHUB_ISSUES=yes**: `gh issue create` で親 + 子 issue を起票（4 レーン割当含む）
  ```bash
  gh issue create --title "[parent] $PROJECT_NAME 全体" --label parent --body-file ...
  gh issue create --title "[task] auth: メール検証" --label "child,lane/1" --body-file ...
  ```
  - `gh auth status` が NG なら `dev/docs/task/INITIAL_ISSUES.md` に手動起票用リストを書き出す

- **USE_GITHUB_ISSUES=no**: 親/子をファイルとして書き出す（git 管理）:
  ```
  <root>/dev/docs/task/parent/0001-<slug>.md
  <root>/dev/docs/task/child/0001-auth-email-validate.md
  <root>/dev/docs/task/child/0002-auth-password-hash.md
  ...
  ```
  各ファイルは front matter で `parent: 0001` / `lane: 1〜4` / `status: pending` を表現。

#### 7.4 active session pointer を破棄（USE_CODEX=yes だった場合）
   ```bash
   ~/my-harness-generator/scripts/codex-ask.sh --clear-active
   ```

## 対話の進め方（Claude の振る舞い）

- 質問は短く 1 ターン 1 問。複数を一度に聞かない。
- 回答受領 → **マスク** → `docs/spec/<stage>.md` と `docs/talk/<stage>.md` に追記、の順を毎ターン守る。
- 機密に該当しそうな文字列を見たら、書き出す前にユーザーへ「これマスクしますね」と一言。
- USE_CODEX=yes のとき、Claude は **Bash ツールで** `codex-ask.sh` を起動する。`--set-active` 済みなので `cd` も `--session` も不要。
- 各段階の終わりに `docs/spec/<stage>.md` を表示し「次へ進む？」を確認。
- ユーザーが「やめる」と言ったら現在の状態を保存して停止。

## Codex 役割の使い分け（チートシート）

| 状況 | role |
|------|------|
| 前提を疑う、対立仮説を出す | critic |
| 要件のあいまい・矛盾検出 | analyst |
| 順序・依存・リスク整理 | planner |
| 設計妥当性・トレードオフ | architect |
| デザイン提案 / 画像生成 | designer |
| 仕様書の論理レビュー | code-reviewer |
| セキュリティ観点 | security-reviewer |

## 失敗時のフォールバック

- `codex` 未インストール → USE_CODEX を自動で no、Claude 単独続行
- `codex login` 未実行 → ユーザーに案内、3 回失敗で no に倒す
- `bootstrap.sh` 実行失敗 → stderr を表示しユーザー判断
- 既存ファイル衝突 → 続行 / 中止 / 別ディレクトリ選択をユーザーに確認

## 成果物まとめ

```
<root>/
├── .my-harness/                       内部作業（gitignore）
│   ├── .config                          選択肢
│   ├── answers.txt                      bootstrap 入力
│   ├── codex-sessions/<KEY>.id          (gitignore)
│   ├── codex-stage*.md                  (gitignore)
│   └── codex.jsonl                      (gitignore)
├── dev/                                 bootstrap が作る通常構成
│   └── docs/
│       ├── spec/01-problem.md ...       マスク済要件
│       ├── design/logo-*.png ...        生成画像
│       ├── talk/01-problem.md ...       マスク済 Q&A 全文
│       └── task/                        USE_GITHUB_ISSUES=no のとき
│           ├── parent/0001-*.md
│           └── child/0001-*.md
├── stage/  main/  lanes/                通常の worktree
└── .bare/                               bare git
```
