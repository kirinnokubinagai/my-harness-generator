---
name: harness-check-secrets
description: ファイル内に環境変数キー直書き / API キー / 本番 DSN / 平文 .env 等の機密値が含まれていないかチェックする。`check-forbidden-patterns.sh` をラップ。「機密チェック」「secrets スキャン」「ハードコード検出」等の文脈で発火。
---

# harness-check-secrets

`gitleaks` では拾いきれないハードコード機密パターンを独自検出する。pre-commit で自動実行されるが、Claude が **commit 前に手動チェック** したいときに呼ぶ。

## 呼び出し

```bash
bash <root>/.my-harness/scripts/check-forbidden-patterns.sh <files...>
```

例:
```bash
bash .my-harness/scripts/check-forbidden-patterns.sh src/auth.ts src/db/client.ts
# 全変更ファイルを対象に
bash .my-harness/scripts/check-forbidden-patterns.sh $(git diff --name-only)
```

## 検出対象

- 環境変数キー直書き（`JWT_SECRET = "abc..."` 等）
- URL 内認証情報（`https://user:pass@host`）
- 本番想定 DSN（`postgres://user:pass@prod...`）
- 平文 `.env` / `.env.local` のコミット（`.env.example` のみ可）

## 判定

- exit 0: OK、機密無し
- exit 1: 違反検出 → 標準エラーに違反箇所と対処方法を出力

## 補完関係

| 仕組み | 何を防ぐ | タイミング |
|--------|----------|------------|
| `harness-mask` skill | 会話 / docs/talk への漏洩 | 書き込み前 |
| この skill | コードへの直書き | commit 前 |
| `gitleaks` (pre-commit) | 既知パターン（API キー文字列） | commit 時 |
| pre-push の履歴 scan | 既コミット済の漏洩 | push 時 |
| 定期 `scheduled-secrets-scan.yml` | 履歴全体の最終 scan | 毎日 |

## 違反時の対処

1. 直書き値を環境変数化
2. SOPS で暗号化したファイル（`*.enc.json`）に移動
3. 詳細は `harness-no-hardcoded-secrets` skill 参照

## 関連

- マスキング: `harness-mask`
- ハードコード禁止規約: `harness-no-hardcoded-secrets`
