---
name: harness-mask
description: 機密値（API キー / メール / 電話 / URL認証 / カード / JWT / PEM 鍵 等）を <MASKED:type> プレースホルダに置換する。docs/talk / docs/spec へ書き込む前、ログを表示する前に必ず通す。「機密マスク」「秘密情報を隠す」等の文脈で発火。
---

# harness-mask

機密値を機械的にマスクして、ファイル書き出しや表示で漏洩しないようにする skill。
`UserPromptSubmit` フックでも自動で適用されるが、Claude が **明示的に** 通すべき場面がある。

## 必ずマスクすべき場面

| 場面 | 操作 |
|------|------|
| `docs/talk/*.md` への書き込み | パイプ通す |
| `docs/spec/*.md` への書き込み | パイプ通す |
| Codex に文脈ファイルとして渡す前 | 通す |
| issue / PR 説明文に貼る前 | 通す |
| ユーザーに表示する長文ログ | 通す |

## 呼び出し方

### stdin 経由
```bash
echo "$user_response" | bash ~/my-harness-generator/scripts/mask-secrets.sh >> dev/docs/talk/01-problem.md
```

### ファイル経由
```bash
bash ~/my-harness-generator/scripts/mask-secrets.sh /tmp/raw.md > dev/docs/spec/01-problem.md
```

### 既存ファイルを上書きマスク
```bash
TMP=$(mktemp)
bash ~/my-harness-generator/scripts/mask-secrets.sh existing.md > "$TMP"
mv "$TMP" existing.md
```

## マスク対象（9 種）

| 入力例 | 出力 |
|--------|------|
| `sk-ant-abcd1234...` | `<MASKED:api-key>` |
| `ghp_abcdef...` | `<MASKED:api-key>` |
| `xoxb-...` / `xoxp-...` | `<MASKED:api-key>` |
| `sk_live_...` | `<MASKED:api-key>` |
| `AKIA...` | `<MASKED:aws-key>` |
| `eyJ...eyJ...sig` | `<MASKED:jwt>` |
| `https://user:pass@host` | `<MASKED:url-cred>@host` |
| `user@example.com` | `<MASKED:email>` |
| `09012345678` | `<MASKED:phone>` |
| `4111-1111-1111-1111` | `<MASKED:cc>` |
| `-----BEGIN PRIVATE KEY-----...` | `<MASKED:private-key>` |
| `JWT_SECRET=xxx` 形式 | `JWT_SECRET=<MASKED:secret>` |
| GCP service_account JSON | `<MASKED:gcp-sa>` |

## 二重防御の構造

```
[ユーザー入力] → [UserPromptSubmit hook] → 自動 mask → docs/talk/<date>.md
                                                ↓
                                           git に commit
                                                ↓
                                  [pre-commit] → gitleaks + forbidden-patterns で再チェック
                                                ↓
                                           push（誤検出時はここで止まる）
```

Claude が明示的に呼ぶのはフックを経ない経路（Write ツールで docs/spec/ に書く等）の保険。

## False positive 注意

- 例: テスト用ダミーアドレス `test@example.com` → マスクされる
- これで困る場合は `harness-mask` を通さず、直接書く（ただしユーザー確認）
- `.env.example` 内のサンプル値もマスクされるが、それは安全側

## チェック

- [ ] docs/talk への書き込みで mask-secrets.sh を経由した
- [ ] docs/spec への書き込みで mask-secrets.sh を経由した
- [ ] Codex に渡すファイルで mask-secrets.sh を経由した
- [ ] pre-commit でも gitleaks が二重防御として走る
