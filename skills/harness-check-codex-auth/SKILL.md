---
name: harness-check-codex-auth
description: Codex CLI のインストール状況とログイン状態を確認する。`check-codex-auth.sh` をラップ。「Codex 使えるか」「codex login」「Codex 認証」等の文脈で発火。
---

# harness-check-codex-auth

Codex CLI（`@openai/codex`）が使える状態かを判定する。`/my-harness-init` の段階 0 や、Codex 連携を始める前に必ず通す。

## 呼び出し

```bash
bash ${CLAUDE_PLUGIN_ROOT:-/my-harness-generator}/scripts/check-codex-auth.sh
```

## 結果

| stdout | exit code | 意味 | 対処 |
|--------|-----------|------|------|
| `logged-in` | 0 | OK、`codex exec` が動く | 続行 |
| `not-logged-in` | 1 | CLI はあるが未ログイン | `codex login` を案内 |
| `not-installed` | 127 | CLI がインストールされていない | `npm i -g @openai/codex` を案内 |

## 判定ロジック

- `command -v codex` で CLI 存在確認
- `~/.codex/auth.json` の存在確認
- jq で `tokens.access_token` / `tokens.id_token` / `api_key` のいずれかが空でないか確認

## 失敗時の案内テンプレ

`not-installed`:
```
Codex CLI が見つかりません。次を実行してください:
  npm install -g @openai/codex
  codex login
```

`not-logged-in`:
```
Codex CLI はあるが認証されていません。次を実行してください:
  codex login
完了後、もう一度試してください。
```

## 関連

- Codex に質問する: `harness-codex-consult`
- `/my-harness-init` 段階 0 で USE_CODEX=yes を選んだ際にこの skill が呼ばれる
