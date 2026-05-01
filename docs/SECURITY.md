# セキュリティ規約（質問16への回答）

## レイヤー別防御

### 1. シークレット管理

- Git に平文の `.env` を絶対にコミットしない（`.gitignore` で防止済み）。
- 開発: **direnv + Nix flake** でローカル環境変数を pure に注入。
- 共有: **SOPS + age** で暗号化したファイルのみリポジトリに含める。
  - 鍵は 1Password / iCloud Keychain で個人管理、CI には `AGE_KEY` を Secret 設定。
- 本番: **AWS Secrets Manager** または **GCP Secret Manager**。アプリは IAM Role で取得。

### 2. 認証・認可

- パスワード: bcrypt cost ≥ 12（`~/.claude/rules/security.md` 参照）。
- セッション: HttpOnly + Secure + SameSite=Strict Cookie、JWT は短命 (15m) + リフレッシュ (7d)。
- 認可: リソース所有者チェック必須、RBAC は Hono ミドルウェアで集中管理。

### 3. 入力検証

- すべての入力を Zod スキーマで検証（拒否は 422 + 日本語エラー）。
- ORM は Drizzle、生 SQL を書く場合は必ず `sql` テンプレートリテラルでパラメータ化。

### 4. SAST / DAST / 依存

| 種別 | ツール | 実行タイミング |
|------|--------|----------------|
| SAST | Semgrep (OWASP / typescript ruleset) | PR → dev |
| Secrets scan | gitleaks | pre-commit + CI |
| Dependency | Trivy + Renovate | CI 毎日 + PR |
| Container | Trivy image scan | docker build 後 |
| DAST | OWASP ZAP baseline + full | dev → stage マージ時 |
| License | license-checker | リリース前 |

### 5. ネットワーク / インフラ

- HTTPS 強制 + HSTS preload。
- CSP は `default-src 'self'` を起点に必要なオリジンのみ追加。
- CORS は許可オリジンを `.env` で明示、`*` は禁止。
- WAF: Cloudflare or AWS WAF（OWASP Core Rule Set）。
- レート制限: ログイン 5 回 / 15 分、API 全体 100 req / 15 分。

### 6. 観測性

- 構造化ログ (pino) → CloudWatch / Datadog。
- 機密情報マスク（メールは `te***@example.com` 形式）。
- メトリクス: p95 レイテンシ、エラー率、認証失敗回数のアラート設定。
- 監査ログ: 認証・権限変更・データ削除は別ストアに 1 年保存。

## なぜこの構成か

- **Nix pure + SOPS**: 「何も入っていない PC」要件を満たし、シークレットも Git で安全に共有可能。
- **Semgrep + Trivy + ZAP**: SAST/DAST/SCA を OSS のみで網羅。
- **stage で ZAP/E2E**: 本番ライク環境で副作用を検出、main は常にグリーン保証。
