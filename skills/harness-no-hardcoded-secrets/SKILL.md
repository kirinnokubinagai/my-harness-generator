---
name: harness-no-hardcoded-secrets
description: 機密値・API キー・接続文字列のハードコードを絶対禁止。環境変数 / SOPS 暗号化 / Secrets Manager のみ許可。pre-commit が機械的に弾く。「環境変数」「API キー」「DATABASE_URL」「秘密鍵」「.env」等の文脈で発火。
---

# harness-no-hardcoded-secrets

ハーネス配下のコード / 設定 / コミットで、機密値の **直書き禁止**。

## 鉄則

| 種類 | 直書き |
|------|--------|
| API キー（`sk-...`, `ghp_...`, `xoxb-...` 等） | **禁止** |
| 環境変数として扱うべき値（`JWT_SECRET`, `DATABASE_URL` 等） | **禁止** |
| URL 内認証情報（`https://user:pass@host`） | **禁止** |
| 本番想定 DSN（`postgres://prod...`） | **禁止** |
| 平文 `.env` のコミット | **禁止**（`.env.example` のみ可） |
| PEM 形式秘密鍵 | **禁止** |

pre-commit が機械的に弾く（漏れは bug）:
- `.gitleaks.toml` + `gitleaks protect`
- `check-forbidden-patterns.sh`（独自パターン）

## 許可される書き方

```ts
// ✅ 環境変数経由
const jwtSecret = process.env.JWT_SECRET ?? (() => {
  throw new Error('JWT_SECRET が未設定です');
})();

// ✅ Cloudflare Workers バインディング
export default {
  async fetch(request, env) {
    const apiKey = env.RESEND_API_KEY;  // wrangler.toml で binding
  }
};

// ✅ SOPS 復号
const { OPENAI_API_KEY } = JSON.parse(
  await sopsDecrypt('secrets/openai.enc.json')
);
```

## 禁止される書き方

```ts
// ❌ 直書き
const JWT_SECRET = "abc12345abcdefghijk";

// ❌ DSN 直書き
const DATABASE_URL = "postgres://user:pass@prod.db.example.com/app";

// ❌ URL 認証
fetch("https://admin:s3cret@api.example.com/x");

// ❌ 平文 .env をコミット
// .env をコミット対象に追加 → pre-commit で拒否
```

## 共有が必要な機密の扱い

### SOPS + age（推奨）
- 暗号化したファイル `secrets/cloudflare.enc.json` を git にコミット
- 復号鍵は各メンバーが個別管理（1Password / iCloud Keychain）
- CI は `AGE_SECRET_KEY` を GitHub Secrets で持つ

### GitHub Secrets / Variables
- ランタイムでのみ使う API キーは Secrets
- 公開可能な設定値（URL 等）は Variables
- 詳細は `docs/SETUP.md`

## 環境変数の必須チェック（起動時）

```ts
const requiredEnvVars = [
  'JWT_SECRET',
  'RESEND_API_KEY',
  'CLOUDFLARE_API_TOKEN',
];
for (const name of requiredEnvVars) {
  if (!process.env[name]) {
    throw new Error(`環境変数 ${name} が未設定です`);
  }
}
```

## マスキング（スキル `harness-mask` 参照）

会話 / ログに機密値が含まれそうなときは `mask-secrets.sh` を通す:
```bash
echo "$content" | bash ${CLAUDE_PLUGIN_ROOT:-/my-harness-generator}/scripts/mask-secrets.sh > docs/talk/01.md
```

## チェック

- [ ] grep で `JWT_SECRET\s*=\s*["']` 等を全 source 検索しヒット無し
- [ ] `.env` が `.gitignore` 配下、`.env.example` のみコミット
- [ ] pre-commit が gitleaks + forbidden-patterns で通った
- [ ] `nix develop --command bash .my-harness/scripts/check-forbidden-patterns.sh <files>` を CI でも実行
