---
name: my-harness-init
description: 新規プロジェクトのインタビュー → 仕様書生成 → ハーネス自動構築までを一気通貫で行う。Claude が最小限の直接質問だけ進め、必要なら Codex に第二意見を求め、ロゴ・UI モックを Codex 経由で gpt-image-2 生成し、最後に bootstrap.sh を非対話モードで実行してプロジェクトを起動する。
---

# /my-harness-init

「何を作るか曖昧」な状態から **システム構築に必要な情報だけ** を対話で確定し、その仕様で **そのままハーネスを構築** するスラッシュコマンド。

## 設計原則

- **聞くのはシステム判断に直結する情報のみ**。マーケティング・ブランド戦略・将来ビジョン等は聞かない。
- **質問は具体的に**。抽象的な質問（「ブランドの世界観」「トーン」「デバイス中心」等）を Claude が improvise すると会話が無駄に長くなるので、SKILL.md で質問文を固定する。
- **1 ターン 1 問**。まとめ聞き禁止。
- **答えやすい選択肢を提示**。自由記述より y/n や列挙肢を優先。

## このスキルの実行主体

このスキルは **Claude（あなた）** が実行する手順書。Codex は外部の補助 LLM として、**Claude が Bash で `codex-ask.sh` を起動して** 質問を投げ、回答を読み取って取り込む形で連携する。Codex は Claude の代わりにユーザーと直接対話しない。

## 必須前提

- `~/my-harness-generator/scripts/bootstrap.sh` が存在する
- Codex 連携時のみ: `~/my-harness-generator/scripts/codex-ask.sh` と `check-codex-auth.sh` が存在し実行権限あり

## 永続成果物の配置（プロジェクトルート配下）

| ディレクトリ | 用途 | git 管理 |
|--------------|------|----------|
| `<root>/dev/docs/spec/` | 仕様書 | あり |
| `<root>/dev/docs/design/` | ロゴ / OG 画像 / UI モック | あり |
| `<root>/dev/docs/talk/` | 会話ログ（マスク済） | あり |
| `<root>/dev/docs/task/` | タスク（USE_GITHUB_ISSUES=no のとき） | あり |
| `<root>/.my-harness/` | 内部作業（codex session id 等） | gitignore 除外 |

## 機密マスキング（厳守）

ユーザーの会話に以下が含まれたらファイル書き出し前に必ずマスク:

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

`docs/talk/` `docs/spec/` への書き込み前に適用。判断に迷うときはユーザーに確認。git pre-commit の `gitleaks` + `check-forbidden-patterns.sh` でも二重に弾く。

## フロー（5 フェーズ）

各フェーズで:
1. ユーザーに **下記の固定質問だけ** を 1 ターン 1 問
2. 回答を **マスク後** で `docs/spec/<phase>.md` と `docs/talk/<phase>.md` に追記
3. USE_CODEX=yes かつフェーズ末尾なら Codex consult を 1 回だけ流す（必須ではない）
4. フェーズ末でユーザーに「次へ進む？」を確認

---

### Setup フェーズ（起動 + 各種選択）

以下を **1 問ずつ** 確認する:

1. プロジェクトのルートディレクトリ（既定: `~/<project-name>`）
2. プロジェクト名（slug、英小文字 + ハイフン）
3. Codex 連携を使う？（y / n）
   - y: 各フェーズ末で Codex に第二意見、デザインフェーズで画像生成
   - n: Claude 単独で進める
4. y のとき: Codex ログイン状態確認:
   ```bash
   bash ~/my-harness-generator/scripts/check-codex-auth.sh
   ```
   - `not-installed` → `npm i -g @openai/codex` を案内、再選択
   - `not-logged-in` → `codex login` を実行してもらう。3 回失敗で自動 n
   - `logged-in` → 続行
5. y のとき: session 名（既定: `my-harness-init`）
6. タスク管理方式: GitHub Issue or ローカル `docs/task/`
7. グローバル `~/.claude/CLAUDE.md` 引き継ぎ y/n

回答を保存:

```bash
mkdir -p <root>/.my-harness <root>/dev/docs/spec <root>/dev/docs/design <root>/dev/docs/talk <root>/dev/docs/task

cat > <root>/.my-harness/.config <<EOF
PROJECT_NAME=<slug>
ROOT=<root>
USE_CODEX=<yes|no>
CODEX_SESSION=<session>            # USE_CODEX=yes のときのみ
USE_GITHUB_ISSUES=<yes|no>
USE_GLOBAL_CLAUDE=<yes|no>
EOF
```

USE_CODEX=yes のとき active session pointer を登録:
```bash
~/my-harness-generator/scripts/codex-ask.sh --set-active <root>
```

---

### フェーズ 1: 何を作るか

**固定質問（1 ターン 1 問、絶対に improvise しない）**:

1. **「一言で何を作りますか？」**（例: タスク管理アプリ / 在庫管理 SaaS / ブログサイト / 社内ツール）
2. **「MVP に必要な機能を 3〜7 個リストアップしてください」**（番号付き）

これだけ。「誰が使うか / ペルソナ / 既存サービスではダメな理由 / 5 年後の成功状態」等は **聞かない**。誰が使うかは、後続の Phase 3（認証）・Phase 5（印象）で直接的な選択肢として現れるため、抽象的に聞く意味がない。

保存先: `dev/docs/spec/01-what.md` / `dev/docs/talk/01-what.md`

USE_CODEX=yes なら末尾で Codex consult:
```bash
~/my-harness-generator/scripts/codex-ask.sh --role analyst \
  --out <root>/.my-harness/codex-phase1.md \
  "プロジェクト概要: <一言>。MVP 機能リスト: <列挙>。論理矛盾・曖昧さ・抜け漏れを指摘してください。"
```

---

### フェーズ 2: プラットフォーム + フレームワーク

**ターゲットごとに 2 段階で訊く**: まず y/n、y のときフレームワーク選択。**1 ターン 1 問厳守、まとめ聞き禁止**。

#### 2.1 Web

1. **Web フロントエンド作る？** y/n
2. y のとき: **どのフレームワーク？**（選択肢: `nextjs` / `tanstack`）
   - `nextjs`: Next.js 16（App Router）
   - `tanstack`: TanStack Start（SSR + TanStack Router）

#### 2.2 iOS

1. **iOS アプリ作る？** y/n
2. y のとき: **どの実装？**（選択肢: `swift` / `expo` / `flutter`）
   - `swift`: Swift + SwiftUI ネイティブ
   - `expo`: React Native (Expo)
   - `flutter`: Flutter

#### 2.3 Android

1. **Android アプリ作る？** y/n
2. y のとき: **どの実装？**（選択肢: `kotlin` / `expo` / `flutter`）
   - `kotlin`: Kotlin + Jetpack Compose ネイティブ
   - `expo`: React Native (Expo)
   - `flutter`: Flutter

#### 2.4 Desktop

1. **デスクトップアプリ作る？** y/n
2. y のとき: **どのフレームワーク？**（選択肢: `tauri` / `electron`）
   - `tauri`: Rust シェル + Web フロントエンド、軽量
   - `electron`: Node.js シェル + Web フロントエンド、エコシステム豊富
3. y のとき: **対応 OS は？**（macOS / Windows / Linux 複数選択可、既定: 全部）

#### バリデーション

- 最低 1 つのプラットフォームが y であること（全部 n なら聞き直し）
- iOS と Android 両方 y で、`expo` または `flutter` を両方選んだ場合 → **同一 codebase で共通化される旨を案内**（`mobile/` ディレクトリに 1 つ）
- iOS と Android で `swift` + `kotlin` の組み合わせ → 別 codebase（`ios/` と `android/`）
- iOS と Android で `expo` と `flutter` のように違うクロスプラットフォーム → 不整合を警告し、片方に揃えるか提案

保存先: `dev/docs/spec/02-platform.md` / `dev/docs/talk/02-platform.md`

`.my-harness/.config` に追記:
```bash
USE_WEB=<yes|no>
WEB_KIND=<nextjs|tanstack>          # USE_WEB=yes のときのみ
USE_IOS=<yes|no>
IOS_KIND=<swift|expo|flutter>       # USE_IOS=yes のときのみ
USE_ANDROID=<yes|no>
ANDROID_KIND=<kotlin|expo|flutter>  # USE_ANDROID=yes のときのみ
USE_DESKTOP=<yes|no>
DESKTOP_KIND=<tauri|electron>       # USE_DESKTOP=yes のときのみ
DESKTOP_OS=macos,windows,linux      # USE_DESKTOP=yes のときのみ
```

**重要（バグ防止）**: フレームワーク選択は **そのプラットフォームの y/n が yes のときに限り** 訊く。1 つのフレームワーク選択が他のプラットフォームに波及することは絶対にない（例: DESKTOP_KIND=tauri を選んだからといって IOS_KIND が tauri になることはない）。

---

### フェーズ 3: バックエンド構成

**固定質問（1 ターン 1 問）**:

1. **バックエンド作る？** y/n（純粋なフロントエンドのみ・サーバーレスで動作するなら no も可）
2. y のとき: **どの言語/フレームワーク？**（選択肢: `hono` / `gin` / `rust`）
   - `hono`: TypeScript + Hono on Cloudflare Workers（軽量・エッジ）
   - `gin`: Go + Gin（高パフォーマンス・標準的）
   - `rust`: Rust + axum（型安全・最高速）
3. **DB 必要？** y/n
4. y のとき: **どの DB？**（選択肢: `d1` / `postgres` / `mysql` / `sqlite`）
   - 推奨: `hono` バックエンドなら `d1`、`gin` / `rust` バックエンドなら `postgres`
5. **メール送信必要？** y/n（y → Resend、パスワードリセット等）
6. **認証どこまで必要？**（選択肢: `none` / `password` / `oauth`）
7. **E2E テストどこまで？**（選択肢: `web` / `mobile` / `both` / `none`）
   - `web` → Playwright、`mobile` → Maestro、`both` → 両方、`none` → なし
8. **CI で Claude Code Action 使う？** y/n（PR レビュー自動化）
9. y のとき: **認証方式**（`api` / `oauth`）

保存先: `dev/docs/spec/03-backend.md` / `dev/docs/talk/03-backend.md`

`.my-harness/.config` に追記:
```bash
USE_BACKEND=<yes|no>
BACKEND_KIND=<hono|gin|rust>        # USE_BACKEND=yes のときのみ
USE_DB=<yes|no>
DB_KIND=<d1|postgres|mysql|sqlite>  # USE_DB=yes のときのみ
USE_EMAIL=<yes|no>
AUTH_KIND=<none|password|oauth>
E2E_SCOPE=<web|mobile|both|none>
USE_PLAYWRIGHT=<yes|no>             # E2E_SCOPE が web|both なら yes
USE_MAESTRO=<yes|no>                # E2E_SCOPE が mobile|both なら yes
USE_CLAUDE_ACTION=<yes|no>
CLAUDE_AUTH=<api|oauth>             # USE_CLAUDE_ACTION=yes のときのみ
```

**重要（バグ防止）**: BACKEND_KIND の選択が他の変数に波及することは絶対にない（例: BACKEND_KIND=rust を選んだからといって DESKTOP_KIND が rust 系の何かになることはない、それぞれ独立）。

USE_CODEX=yes なら Codex に architect 観点で確認:
```bash
~/my-harness-generator/scripts/codex-ask.sh --role architect \
  --out <root>/.my-harness/codex-phase3.md \
  "プラットフォーム: <Web/iOS/Android/Desktop>。バックエンド: <DB/Email/Auth/E2E>。設計妥当性とトレードオフを指摘してください。"
```

---

### フェーズ 4: データモデル（USE_DB=yes のときのみ。no ならスキップ）

**固定質問**:

1. **エンティティを 3〜7 個リストアップしてください**（例: User / Task / Comment）
2. **各エンティティの主要フィールドを箇条書きで**
3. **エンティティ間の関係を mermaid ER 風に**（例: User 1—N Task）
4. **PII を含むフィールドはどれですか？**（メアド・電話・住所等）

Claude が回答から mermaid ER 図を組み立てて `dev/docs/spec/04-data-model.md` に保存。

USE_CODEX=yes なら architect で正規化チェック。

---

### フェーズ 5: ビジュアル（ロゴ + 主要画面 UI モック）

**画像形式の絶対ルール**:
- **PNG のみ**。SVG は **禁止**（生成する画像形式として）。透過 PNG（背景アルファ）は許可。
- 解像度: ロゴ最低 1024×1024、UI モックは下記指定の解像度を厳守
- 生成後は **必ず `open` コマンドで自動オープン**（macOS）してユーザーが即座に確認できるようにする
  - macOS: `open <path>`
  - Linux: `xdg-open <path>`
  - Windows: `start "" <path>`
  - Claude は `uname` で OS を判定して適切なコマンドを選ぶ

**プロンプトの方針**: Codex のデザイナー能力を信頼し、**ざっくり依頼して任せる**。

Claude が細かく specify せず、`--context dev/docs/spec/*.md` で仕様書を Codex に渡し、「ロゴ 3 案を PNG で生成して、保存先は ...」程度の短い依頼にする。色・形・レイアウトの判断は Codex 任せ。

絶対に書かない:
- コード風指示（座標、ピクセル指定、CSS プロパティ、Tailwind クラス、SVG パス、HTML タグ）
- 「こうしろ」と細部まで指定すること

書くこと:
- 何を作るか（ロゴ / 画面名）と何案
- PNG であること、保存パス、解像度（1024×1024 など）
- Codex が context（spec ファイル）を読んでくれる前提

**固定質問**（1 ターン 1 問、最小限）:

1. **主色のヒントは？**（任意、例: `#14b8a6` / 「青系」 / 「未指定で OK」）
2. **モックを作りたい画面を 3〜5 個挙げてください**（例: ログイン / ホーム / 詳細 / 設定）

これだけ。ロゴの方向性・印象・トーン等は **聞かない**。Codex が `dev/docs/spec/*.md` を読んで判断する。

#### ロゴ生成（USE_CODEX=yes のとき）

```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh \
  --role designer \
  --context <root>/dev/docs/spec/*.md \
  --out <root>/.my-harness/codex-logo.md \
  "$PROJECT_NAME のロゴを 3 案、PNG で生成してください（SVG 禁止、1024x1024 以上、透過背景）。
仕様書を読んでプロジェクトに合うデザインを Codex の判断で作ってください。<主色ヒントがあれば: 主色は <ヒント>>

保存先:
- <root>/dev/docs/design/logo-1.png
- <root>/dev/docs/design/logo-2.png
- <root>/dev/docs/design/logo-3.png"
```

生成完了後、3 案を即座にオープン（macOS の例）:

```bash
open <root>/dev/docs/design/logo-1.png \
     <root>/dev/docs/design/logo-2.png \
     <root>/dev/docs/design/logo-3.png
```

Linux なら `xdg-open` を 3 回、Windows なら `start "" <path>` を 3 回。`uname -s` で分岐。

**ファイル形式の検証**（生成直後に必ず実行）:
```bash
file <root>/dev/docs/design/logo-{1,2,3}.png | grep -v "PNG image"
```
PNG 以外（SVG / JPEG など）が混じっていたら Codex に再生成依頼。SVG が生成された場合は削除して PNG で再生成。

ユーザーが 1 案選定 → `<root>/dev/docs/design/logo-final.png` に copy（symlink ではなく実体 copy、git 管理しやすくするため）。

#### UI モック生成（主要画面ごと）

各画面について:

```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh \
  --role designer \
  --context <root>/dev/docs/spec/*.md <root>/dev/docs/design/logo-final.png \
  --out <root>/.my-harness/codex-mock-<画面>.md \
  "$PROJECT_NAME の <画面名> 画面のモックを 2 案、PNG で生成してください（SVG 禁止）。
解像度: <Web/Desktop なら 1280x800、モバイルなら 375x812>

仕様書とロゴ採用案を踏まえて、Codex の判断でデザインしてください。Lucide Icons 使用。

保存先:
- <root>/dev/docs/design/mock-<画面>-1.png
- <root>/dev/docs/design/mock-<画面>-2.png"
```

生成完了後、2 案を即座にオープン:
```bash
open <root>/dev/docs/design/mock-<画面>-{1,2}.png
```

PNG 検証も同様に `file` コマンドで実施。各画面 2 案 → ユーザー選定。OG 画像 / favicon も同方式（**全部 PNG**）。

#### iteration（重要）

モックを見て要件が変わったら **フェーズ 1〜4 のどれかに戻って仕様修正**。修正後にこのフェーズに戻ってモック更新（差分のみ再生成可）。**最大 3 回まで**。

USE_CODEX=no のときはモック生成はスキップし、`dev/docs/design/brand.md` に方針（主色・印象・各画面のレイアウト方針）をテキストで記録。後でユーザーが Figma 等で手作業。

#### 完了基準

- [ ] ロゴ採用案 1 個確定
- [ ] 主要画面 3〜5 個のモック選定済（USE_CODEX=yes のみ）
- [ ] OG 画像 / favicon 生成済
- [ ] iteration で仕様変わったなら `docs/spec/*.md` も最新

保存先: `dev/docs/spec/05-visual.md` / `dev/docs/design/{logo-*,mock-*,og,favicon}.png`

---

### フェーズ 6: 仕様確定 + bootstrap + issue/task 生成

#### 6.1 仕様の最終確認

`dev/docs/spec/0[1-5]-*.md` を Read で全部読み、概観をユーザーに提示し承認を得る。

USE_CODEX=yes なら Codex code-reviewer に最終 cross-check:
```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh --role code-reviewer \
  --context <root>/dev/docs/spec/*.md <root>/dev/docs/design/*.png -- \
  "仕様 / モック / 技術スタックの整合性、論理矛盾、機能漏れを指摘してください。"
```

修正があればフェーズ 1〜5 のどこかに戻ってから再度ここに来る。

#### 6.2 bootstrap 実行（非対話）

```bash
bash ${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/bootstrap.sh "<root>" --config "<root>/.my-harness/.config"
```

bootstrap が dev worktree に scaffold を作り初期コミット → `docs/spec/`, `docs/design/`, `docs/talk/` も含まれて git 管理される。

#### 6.3 issue / task 生成（USE_GITHUB_ISSUES に応じ分岐）

フェーズ 1 の機能リストから **300 行以内の子 issue** に分割し、ファイル衝突防止のためファイル所有を宣言。

- **USE_GITHUB_ISSUES=yes**: `gh issue create` で親 + 子 issue を起票（4 レーン割当含む）
- **USE_GITHUB_ISSUES=no**: 親/子をファイルで:
  ```
  <root>/dev/docs/task/parent/0001-<slug>.md
  <root>/dev/docs/task/child/0001-<feature>.md
  ```
  各ファイルは front matter で `parent: 0001` / `lane: 1〜4` / `status: pending` を表現。

#### 6.4 active session pointer を破棄（USE_CODEX=yes だった場合）

```bash
~/my-harness-generator/scripts/codex-ask.sh --clear-active
```

---

## Codex 役割の使い分け（任意）

| 状況 | role |
|------|------|
| 要件のあいまい・矛盾検出 | analyst |
| 設計妥当性・トレードオフ | architect |
| デザイン提案 / 画像生成 | designer |
| 仕様書の論理レビュー | code-reviewer |
| セキュリティ観点 | security-reviewer |

**critic / planner は使わない**（製品戦略寄りで、システム判断に直結しないため）。

## 失敗時のフォールバック

- `codex` 未インストール → USE_CODEX を自動で no、Claude 単独続行
- `codex login` 未実行 → 案内、3 回失敗で no に倒す
- `bootstrap.sh` 実行失敗 → stderr 表示してユーザー判断
- 既存ファイル衝突 → 続行 / 中止 / 別ディレクトリ選択をユーザーに確認

## 成果物まとめ

```
<root>/
├── .my-harness/                       内部作業（gitignore）
│   ├── .config                          選択肢（USE_DESKTOP 等含む）
│   ├── codex-sessions/<KEY>.id          (gitignore)
│   ├── codex-phase*.md                  (gitignore)
│   └── codex.jsonl                      (gitignore)
├── dev/                                 bootstrap が作る通常構成
│   └── docs/
│       ├── spec/01-what.md ...          マスク済要件（5 ファイル）
│       ├── design/logo-*.png ...        生成画像
│       ├── talk/01-*.md ...             マスク済 Q&A 全文
│       └── task/                        USE_GITHUB_ISSUES=no のとき
│           ├── parent/0001-*.md
│           └── child/0001-*.md
├── stage/  main/  lanes/                通常の worktree
└── .bare/                               bare git
```

## 対話の進め方（Claude の振る舞い）

- **本 SKILL.md に書かれた質問文だけを読む**。derivative 質問（「使うデバイスは？」「ブランドの世界観は？」「5 年後は？」等）を勝手に作らない。
- 1 ターン 1 問。まとめ聞き禁止。
- 回答受領 → マスク → ファイル追記、の順を毎ターン守る。
- 機密に該当しそうな文字列を見たら、書き出す前に「これマスクしますね」と一言。
- フェーズ末で要約を提示し「次へ進む？」を確認。
- ユーザーが「やめる」と言ったら現在の状態を保存して停止。
