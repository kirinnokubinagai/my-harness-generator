# エンジニア規約（質問14・15・17・18）

## コーディング（質問14）

### 命名と説明

- 変数・定数名は読み手が一目で理解できる名詞。短縮形・連想ゲームは禁止。
- すべての変数・定数に **JSDoc/TSDoc コメント** を付ける。
- **関数内コメントは禁止**。説明が必要なら関数を分割する。
- 関数・型・モジュールは **TSDoc を必須**。`@param` `@returns` `@throws` `@example` を埋める。

```ts
/**
 * メールアドレスとパスワードからユーザーを作成する
 *
 * @param input - ユーザー登録に必要な入力（Zod 検証済み）
 * @returns 作成されたユーザー。重複時は Result.err
 * @throws DatabaseError - DB 接続失敗時
 */
export async function createUser(input: CreateUserInput): Promise<Result<User>> { ... }
```

### Hono Clean Architecture

```
src/
├── domain/          # エンティティ、値オブジェクト、リポジトリ I/F
├── application/     # ユースケース（オーケストレーション）
├── infrastructure/  # Drizzle 実装、外部 API、Hono ハンドラ
└── interfaces/      # Hono ルーター、入出力 DTO（Zod）
```

依存方向: `interfaces → application → domain ← infrastructure`。
domain は外側に依存しない。infrastructure は domain の I/F を実装する。

### Nix 完全依存（impure 禁止）

- `flake.nix` で Node.js / pnpm / Biome / Playwright / Maestro / Trivy / Semgrep をピン留め。
- `nix develop` 以外の手段でツールを入れない（`brew install` 禁止）。
- CI も `nix develop --command pnpm ci` で実行。
- 例外は Claude Code / Codex / GitHub CLI のみ。
- **direnv 必須**: `.envrc` に `use flake` を書き、`direnv allow` でディレクトリ移動時に自動で nix shell に入る運用とする。
  これにより人間も AI も `nix develop` の打ち忘れによる impure 実行を防げる。

### ハードコード禁止（厳格）

以下はコミット段階で `husky pre-commit` の `forbidden-patterns` チェックが弾く（`.harness/scripts/check-forbidden-patterns.sh`）。

- 環境変数として扱うべき値の **文字列リテラル直書き**
  対象キー: `JWT_SECRET` / `DATABASE_URL` / `*_API_KEY` / `*_TOKEN` / `STRIPE_SECRET` /
  `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `CLOUDFLARE_API_TOKEN` / `AWS_*` / `GITHUB_TOKEN` /
  `SUPABASE_*` / `SENTRY_DSN` / `REDIS_URL` / `SMTP_*` / `SESSION_SECRET` / `ENCRYPTION_KEY` / `WEBHOOK_SECRET`
- `https://user:password@host` のような **URL 内資格情報**
- localhost 以外のホストを指す **本番想定 DSN（`postgres://...` 等）の直書き**
- `.env`（および `.env.local` / `.env.production` 等）の **ファイルそのもののコミット**
  → 許可されるのは `.env.example` のみ

加えて以下のパターンは値そのものが弾かれる（`gitleaks` + 独自ルール `.gitleaks.toml`）。

- Stripe ライブ鍵（`sk_live_...`）
- OpenAI 鍵（`sk-...` / `sk-proj-...`）
- Anthropic 鍵（`sk-ant-...`）
- AWS アクセスキー ID（`AKIA...`）
- GCP サービスアカウント JSON（`"type":"service_account"`）
- Cloudflare API トークン
- GitHub トークン（`ghp_...` / `gho_...` / `ghu_...` / `ghs_...` / `ghr_...`）
- JWT 三段ドット文字列（`eyJ...eyJ...`）
- PEM 形式秘密鍵ブロック

許可される書き方の例:

```ts
/** JWT 署名鍵。環境変数で必ず注入する。未設定なら起動時に例外を投げる。 */
const jwtSigningSecret = process.env.JWT_SECRET ?? (() => { throw new Error('JWT_SECRET が未設定です'); })();
```

### 説明文・コメントは日本語

- TSDoc / JSDoc / ファイル先頭の概要コメントはすべて **日本語で記述する**。
  英語混在を許容するのは固有名詞・型名・コマンド名・URL のみ。
- コミットメッセージの本文も日本語で書く（type プレフィックスは英語の Conventional Commits）。
  例: `feat(auth): メールアドレスでのログイン機能を追加`
- PR の説明・issue の説明・レビューコメントもすべて日本語。
- README / docs もすべて日本語。多言語化が必要な場合のみ英語を併記する。

## デザイン / UX / Accessibility（質問15）

参考: <https://www.shokasonjuku.com/ux-psychology>

### 47 原則のうち最重要 10 を必須適用

1. **Hick の法則**: 選択肢を絞る（1 画面 1 主アクション）。
2. **Fitts の法則**: タップ領域 ≥ 44×44pt、重要 CTA は親指が届く位置。
3. **Miller の法則**: グルーピングは 7 ± 2 を超えない。
4. **Jakob の法則**: 既存の慣習を踏襲（独自 UI を避ける）。
5. **Aesthetic-Usability 効果**: 見た目の整いを軽視しない。
6. **Peak-End ルール**: 最後の体験（成功フィードバック）を丁寧に。
7. **Doherty 閾値**: 操作フィードバック 400ms 以内。
8. **コントラスト**: WCAG AA 4.5:1（本文）/ 3:1（大文字）。
9. **キーボード操作**: フォーカスリング非削除、Tab 順を論理的に。
10. **prefers-reduced-motion**: 必ず尊重。

### 禁止（AI っぽさ排除）

- グラデーション（特に紫〜青〜ピンク）、ネオン、グロー、宇宙背景、浮遊パーティクル。
- 「AI Powered」等の装飾バッジ。

### アイコン

- 絵文字禁止、`lucide-react` のみ使用。`aria-label` 必須（アイコンのみのボタン）。

## E2E（質問17）

| 対象 | ツール | 配置 |
|------|--------|------|
| Web | Playwright | `tests/e2e/web/` |
| Mobile | Maestro | `tests/e2e/mobile/*.yaml` |

- 主要ユーザーフロー（signup, login, 主要 CRUD, paywall, 課金）は必ず網羅。
- データはテスト専用 DB を seed。テスト後にクリーンアップ。
- スクショ + ビデオを失敗時のみ保存。

## レビュアー規約（質問18）

reviewer は **エンジニア規約への違反検出** が最優先タスク。

### チェックリスト（順守確認）

- [ ] `any` / `else` / `console.log` / 関数内コメント がない
- [ ] すべての変数・定数・関数に JSDoc/TSDoc がある
- [ ] 命名が読み手にとって自明である
- [ ] 1 関数 1 責務、ネスト ≤ 3 層
- [ ] Hono は Clean Architecture 4 層分離を守っている
- [ ] DB 操作は Drizzle ORM、`drizzle-kit push` 未使用
- [ ] Zod で全入力を検証、エラーメッセージは日本語
- [ ] 環境変数で機密管理、ハードコード無し
- [ ] Lucide Icons 使用、絵文字なし、AI 風デザイン要素なし
- [ ] Nix flake で固定、impure な参照なし
- [ ] テストが正常系/異常系/境界値を含む
- [ ] エラーは Result 型 or カスタム例外、メッセージは日本語

不備があれば analyst 経由で engineer に修正依頼を出す。
