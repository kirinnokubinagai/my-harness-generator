# OpenClaw — Discord Bot Setup Guide

> **Version:** my-harness-generator 7.30.0 | **Date:** 2026-05-14

---

## English

### Overview

OpenClaw is an open-source self-hosted AI gateway that connects to Discord (and other messaging platforms). It is the alternative to Hermes Agent in the harness — both are mutually exclusive. Choose OpenClaw if you prefer its ecosystem, interface, or model configuration format.

**If you already have a Discord bot from a Hermes Agent setup:** you can reuse the same Discord application and bot token. Skip steps 1–3 and go directly to section 3.5.

---

### 1. Create a Discord Application and Bot

1. Go to **https://discord.com/developers/applications** and sign in.
2. Click **New Application** → give it a name (e.g. `OpenClaw-OCI`).
3. On the left sidebar, click **Bot**.
4. Click **Add Bot** → confirm.
5. Under **Token**, click **Reset Token** → copy the token.
   Store it safely — you will paste it into `/my-harness-init` Q12.5.7 or pass it directly to `scripts/ensure-openclaw-config.sh`.
6. Scroll down to **Privileged Gateway Intents** and enable **all three**:
   - **Presence Intent**
   - **Server Members Intent**
   - **Message Content Intent** ← required for text channel replies
7. Click **Save Changes**.

### 2. Set OAuth2 Permissions (Invite URL)

1. On the left sidebar, click **OAuth2** → **URL Generator**.
2. Under **Scopes**, select:
   - `bot`
   - `applications.commands` (for slash commands like `/focus`, `/agents`, `/session`)
3. Under **Bot Permissions**, select:
   - **Text Permissions:** Send Messages, Read Message History, Add Reactions, Embed Links, Attach Files
   - **Voice Permissions:** Connect, Speak, Use Voice Activity
4. Copy the generated URL at the bottom of the page.

### 3. Invite the Bot to Your Server

1. Paste the OAuth2 URL into a browser tab.
2. Choose your Discord server from the drop-down.
3. Click **Authorize** → complete the CAPTCHA.
4. The bot now appears in your server's member list (offline until OpenClaw starts).

### 3.5. Creating the Two Channels OpenClaw Uses

OpenClaw uses two channels in your Discord server:

1. **Home channel** (e.g. `#bot-updates`): where OpenClaw posts proactive messages — cron output, daily summaries, reminders. The harness stores this as `DISCORD_HOME_CHANNEL_NAME`. Used in Q12.5.9.

2. **Application channel** (e.g. `#bot-chat`): where users talk to OpenClaw via @mention or DM pairing. The harness stores this as `DISCORD_APP_CHANNEL_NAME`. Used in Q12.5.10.

Create both channels **before** the bot's first deploy:

1. Open your Discord server.
2. Click the `+` next to **Text Channels** in the sidebar.
3. Create `bot-updates` (or the name you will give in Q12.5.9).
4. Create `bot-chat` (or the name you will give in Q12.5.10).
5. Ensure the bot has Read/Send permissions on both channels.

**Note:** If you already created these channels for Hermes, you can reuse them for OpenClaw.

---

### 3.6. Choosing an AI Provider for OpenClaw

OpenClaw supports 4 AI backends, the same matrix as Hermes. Choose one during `/my-harness-init` Q12.5.6.

| Provider | Cost | Auth method | Setup |
|----------|------|-------------|-------|
| **Codex** (ChatGPT Plus/Pro) | $0 extra — uses your subscription | CLIProxyAPI wraps `~/.codex/auth.json` | Run `codex login` on your Mac once (Q11) |
| **Claude Code** (Claude Pro/Max) | $0 extra — uses your subscription | CLIProxyAPI wraps `~/.claude/.credentials.json` | Run `claude setup-token` on your Mac once (Q9.5) |
| **OpenRouter** (API key) | Free-tier models available; paid models by usage | Direct connection, `OPENROUTER_API_KEY` env var | Get key at https://openrouter.ai/keys |
| **Anthropic API** (paid) | Pay-per-token | Direct connection, `ANTHROPIC_API_KEY` env var | Get key at https://console.anthropic.com/ |

**Recommendation:** If you have a ChatGPT Plus/Pro or Claude Pro/Max subscription, use **Codex** or **Claude Code** — zero extra cost. CLIProxyAPI runs on the VM (port 8317) and proxies through your CLI OAuth session.

#### CLIProxyAPI (used by Codex and Claude Code providers)

CLIProxyAPI is a Go binary (installed by NixOS) that listens on `localhost:8317` and exposes your CLI subscription as an OpenAI-compatible endpoint. OpenClaw's `agents.defaults.providers.openai.baseUrl` is set to `http://localhost:8317/v1` automatically when you select these providers.

---

### 3.7. Voice Mode

OpenClaw supports voice on Discord voice channels. The OCI VM is headless — CLI interactive voice is disabled. Discord voice channel mode works without a physical microphone (audio travels over Discord's API).

- **TTS:** ElevenLabs (if `ELEVENLABS_API_KEY` is set in `.env`) or system TTS fallback
- **STT:** OpenClaw's built-in transcription (no local Whisper model download required — unlike Hermes)

If voice is not needed, no additional configuration is required; the voice block is commented out in `config.example.yaml`.

---

### 4. Daily-Report Cron

The daily-report cron job is registered automatically by `setup-oci-vm-nixos.sh` via `register-agent-daily-report.sh`. It runs at 09:00 UTC (18:00 JST) daily and posts to `DISCORD_HOME_CHANNEL_NAME`.

The cron command used:

```bash
openclaw cron add \
  --name daily-report \
  --cron "0 9 * * *" \
  --session session:daily-report-<REPO_NAME> \
  --message "<prompt contents>" \
  --announce
```

This uses OpenClaw's session persistence (`session:daily-report-<repo>`) for memory continuity across days — the same pattern as Hermes.

---

### 5. First-Run Smoke Tests

After `setup-oci-vm-nixos.sh` completes and `openclaw.service` is running:

**Text channel test:**
```
@<YourBotName> hello
```
OpenClaw should reply within a few seconds.

**Session test:**
```
/session idle
```
Confirms OpenClaw's session management is working.

**Cron test:**
```bash
ssh -i <key> opc@<ip> "openclaw cron list"
```
Should show the `daily-report` job registered at `0 9 * * *`.

---

### 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Bot online but ignores messages | Message Content Intent not enabled | Developer Portal → Bot → Privileged Intents → enable Message Content |
| `DISCORD_BOT_TOKEN` error in logs | Token wrong or revoked | Developer Portal → Bot → Reset Token → re-run `bash scripts/ensure-openclaw-config.sh <root>` |
| `openclaw.service` fails to start | Config JSON invalid | Check `journalctl -u openclaw -n 50`; re-render config via `setup-oci-vm-nixos.sh` |
| Cron job not firing | `cron.enabled: false` in config | Verify config has `cron.enabled: true`; re-register via `register-agent-daily-report.sh` |
| Voice not working | ElevenLabs key missing | Add `ELEVENLABS_API_KEY=<key>` to `/home/opc/openclaw/.env` and restart the service |
| CLIProxyAPI provider not reachable | `cliproxyapi.service` not running | `sudo systemctl status cliproxyapi.service`; check `journalctl -u cliproxyapi -n 30` |

### 7. Rotate the Bot Token

If the token leaks (e.g. accidentally committed to git):

1. **Developer Portal** → your application → **Bot** → **Reset Token** → copy new token.
2. On your Mac, run:
   ```bash
   bash scripts/ensure-openclaw-config.sh <root> <new-discord-bot-token> <provider> [<credential>]
   # provider: codex | claude-code | openrouter | claude-api
   # credential: empty for codex/claude-code; sk-or-... for openrouter; sk-ant-api... for claude-api
   ```
3. Re-run the deploy script:
   ```bash
   bash scripts/setup-oci-vm-nixos.sh <root>
   ```
4. SSH to the VM and restart OpenClaw:
   ```bash
   sudo systemctl restart openclaw.service
   ```

---

## 日本語

### 概要

OpenClaw はオープンソースのセルフホスト型 AI ゲートウェイで、Discord（その他のメッセージングプラットフォームも対応）に接続します。harness において Hermes Agent と排他選択の関係にあります。OpenClaw のインターフェース・エコシステム・設定フォーマットを好む場合はこちらを選んでください。

**Hermes Agent で Discord ボットを作成済みの場合:** 同じ Discord アプリケーションとボットトークンを再利用できます。手順 1〜3 はスキップしてセクション 3.5 に進んでください。

---

### 1. Discord アプリケーションとボットの作成

1. **https://discord.com/developers/applications** にアクセスしてサインイン。
2. **New Application** をクリック → 名前を入力（例: `OpenClaw-OCI`）。
3. 左サイドバーの **Bot** をクリック。
4. **Add Bot** → 確認。
5. **Token** の下の **Reset Token** をクリック → トークンをコピー。
   安全な場所に保存し、`/my-harness-init` Q12.5.7 に貼り付けるか、`scripts/ensure-openclaw-config.sh` に直接渡します。
6. 下にスクロールして **Privileged Gateway Intents** を全て有効化:
   - **Presence Intent**
   - **Server Members Intent**
   - **Message Content Intent** ← テキストチャンネル返答に必須
7. **Save Changes** をクリック。

### 2. OAuth2 権限の設定（招待 URL）

1. 左サイドバーの **OAuth2** → **URL Generator** をクリック。
2. **Scopes** で以下を選択:
   - `bot`
   - `applications.commands`（`/focus`、`/agents`、`/session` などスラッシュコマンド用）
3. **Bot Permissions** で以下を選択:
   - **テキスト権限:** Send Messages, Read Message History, Add Reactions, Embed Links, Attach Files
   - **ボイス権限:** Connect, Speak, Use Voice Activity
4. ページ下部の生成された URL をコピー。

### 3. ボットをサーバーに招待

1. コピーした OAuth2 URL をブラウザに貼り付け。
2. ドロップダウンから Discord サーバーを選択。
3. **承認** → CAPTCHA を完了。
4. ボットがサーバーのメンバーリストに追加されます（OpenClaw 起動まではオフライン）。

### 3.5. OpenClaw が使う 2 つのチャンネルを作成

OpenClaw は Discord サーバー内で 2 種類のチャンネルを使い分けます:

1. **ホームチャンネル**（例: `#bot-updates`）: OpenClaw が自発的にメッセージを送るチャンネル — 定期タスク出力、日次サマリー、リマインダーなど。harness は Q12.5.9 でこの名前を尋ね、`DISCORD_HOME_CHANNEL_NAME` として保存します。

2. **アプリケーションチャンネル**（例: `#bot-chat`）: ユーザーが @メンション や DM ペアリング経由で OpenClaw と会話するメインチャンネル。harness は Q12.5.10 でこの名前を尋ね、`DISCORD_APP_CHANNEL_NAME` として保存します。

bot の初回デプロイ**前**に、Discord サーバーで両方のチャンネルを作成してください。

**注:** Hermes 用にすでにチャンネルを作成済みの場合は、OpenClaw でそのまま再利用できます。

---

### 3.6. OpenClaw の AI プロバイダを選択

OpenClaw は Hermes と同じ 4 種類の AI バックエンドに対応しています。`/my-harness-init` Q12.5.6 で選択します。

| プロバイダ | コスト | 認証方式 | 設定 |
|-----------|--------|---------|------|
| **Codex**（ChatGPT Plus/Pro） | 追加費用なし（サブスク利用） | CLIProxyAPI が `~/.codex/auth.json` をラップ | Mac で `codex login` を 1 回実行（Q11） |
| **Claude Code**（Claude Pro/Max） | 追加費用なし（サブスク利用） | CLIProxyAPI が `~/.claude/.credentials.json` をラップ | Mac で `claude setup-token` を 1 回実行（Q9.5） |
| **OpenRouter**（API キー） | 無料枠モデルあり、有料モデルは使用量課金 | 直接接続、`OPENROUTER_API_KEY` 環境変数 | https://openrouter.ai/keys でキーを取得 |
| **Anthropic API**（有料） | トークン従量課金 | 直接接続、`ANTHROPIC_API_KEY` 環境変数 | https://console.anthropic.com/ でキーを取得 |

---

### 3.7. 音声モード

OpenClaw は Discord ボイスチャンネルでの音声対話に対応しています。OCI VM はヘッドレスのため CLI インタラクティブ音声は無効ですが、Discord 音声チャンネルモードはマイクなしで動作します（音声は Discord API 経由）。

- **TTS:** ElevenLabs（`.env` に `ELEVENLABS_API_KEY` を設定した場合）またはシステム TTS フォールバック
- **STT:** OpenClaw 内蔵の文字起こし機能（Whisper のローカルモデルダウンロード不要 — Hermes と異なる点）

---

### 4. 初回動作確認

`setup-oci-vm-nixos.sh` が完了し `openclaw.service` が起動したら:

**テキストチャンネルテスト:**
```
@<ボット名> hello
```
数秒以内にボットが応答するはずです。

**cron 確認:**
```bash
ssh -i <key> opc@<ip> "openclaw cron list"
```
`daily-report` ジョブが `0 9 * * *` で登録されているはずです。

### 5. ボットトークンのローテーション

トークンが漏洩した場合:

1. **Developer Portal** → アプリケーション → **Bot** → **Reset Token** → 新しいトークンをコピー。
2. Mac で以下を実行:
   ```bash
   bash scripts/ensure-openclaw-config.sh <root> <new-discord-bot-token> <provider> [<credential>]
   ```
3. デプロイスクリプトを再実行:
   ```bash
   bash scripts/setup-oci-vm-nixos.sh <root>
   ```
4. VM に SSH して OpenClaw を再起動:
   ```bash
   sudo systemctl restart openclaw.service
   ```
