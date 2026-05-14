# Hermes Agent — Discord Bot Setup Guide

> **Version:** my-harness-generator 7.26.0 | **Date:** 2026-05-14

---

## English

### 1. Create a Discord Application and Bot

1. Go to **https://discord.com/developers/applications** and sign in.
2. Click **New Application** → give it a name (e.g. `Hermes-OCI`).
3. On the left sidebar, click **Bot**.
4. Click **Add Bot** → confirm.
5. Under **Token**, click **Reset Token** → copy the token.  
   Store it safely — you will paste it into `/my-harness-init` Q12.7 or pass it directly to `scripts/ensure-hermes-config.sh`.
6. Scroll down to **Privileged Gateway Intents** and enable **all three**:
   - **Presence Intent**
   - **Server Members Intent**
   - **Message Content Intent** ← required for Auto Voice Reply
   - **Voice State Intent** is automatically granted when you add Voice permissions in step 9.
7. Click **Save Changes**.

### 2. Set OAuth2 Permissions (Invite URL)

1. On the left sidebar, click **OAuth2** → **URL Generator**.
2. Under **Scopes**, select:
   - `bot`
   - `applications.commands` (for slash commands like `/join`)
3. Under **Bot Permissions**, select:
   - **Text Permissions:** Send Messages, Read Message History, Add Reactions, Embed Links, Attach Files
   - **Voice Permissions:** Connect, Speak, Use Voice Activity
4. Copy the generated URL at the bottom of the page.

### 3. Invite the Bot to Your Server

1. Paste the OAuth2 URL you just copied into a browser tab.
2. Choose your Discord server from the drop-down.
3. Click **Authorize** → complete the CAPTCHA.
4. The bot now appears in your server's member list (offline until Hermes starts).

### 3.5. Creating the two channels Hermes uses

Hermes uses two channels in your Discord server:

1. **Home channel** (e.g. `#bot-updates`): where Hermes posts proactive messages — cron output, reminders, daily summaries, voice-message replies that came in via DM. The harness asks for this name in Q12.9 and stores it as `DISCORD_HOME_CHANNEL_NAME`.

2. **Application channel** (e.g. `#bot-chat`): where users talk to Hermes via @mention, voice channel join, or direct messages. The harness asks for this name in Q12.10 and stores it as `DISCORD_APP_CHANNEL_NAME` (informational — Hermes itself doesn't gate on this as of 2026-05-14, but the slot reserves it for future Hermes versions).

Create both channels in your Discord server BEFORE running the bot's first deploy:

1. Open your Discord server.
2. Click the `+` next to **Text Channels** in the sidebar.
3. Create `bot-updates` (or whatever name you'll give in Q12.9).
4. Create `bot-chat` (or whatever name you'll give in Q12.10).
5. Make sure the bot has Read/Send permissions on both (the OAuth invite URL from step 2 should have granted them automatically).

After the bot deploys and joins your server, it will recognize the channels by name from the env vars. You can override at any time by running `/sethome` in the desired channel (Hermes writes the channel ID into `config.yaml` — see [known issue #6447](https://github.com/NousResearch/hermes-agent/issues/6447) about its env-vs-yaml destination).

### 3.6. Choosing an AI Provider for Hermes

Hermes supports 4 AI backends. Choose one during `/my-harness-init` Q12.6.

| Provider | Cost | Auth method | Setup |
|----------|------|-------------|-------|
| **Codex** (ChatGPT Plus/Pro) | $0 extra — uses your subscription | CLIProxyAPI wraps `~/.codex/auth.json` | Run `codex login` on your Mac once (Q11) |
| **Claude Code** (Claude Pro/Max) | $0 extra — uses your subscription | CLIProxyAPI wraps `~/.claude/.credentials.json` | Run `claude setup-token` on your Mac once (Q9.5) |
| **OpenRouter** (API key) | Free-tier models available; paid models by usage | Direct connection, `OPENROUTER_API_KEY` env var | Get key at https://openrouter.ai/keys |
| **Anthropic API** (paid) | Pay-per-token | Direct connection, `ANTHROPIC_API_KEY` env var | Get key at https://console.anthropic.com/ |

**Recommendation:** If you have a ChatGPT Plus/Pro or Claude Pro/Max subscription,
use **Codex** or **Claude Code** — you pay nothing extra and the subscription covers
all Hermes Discord replies. CLIProxyAPI runs locally on the VM (port 8317) and
proxies requests through your existing CLI OAuth session.

**Important:** Gemma 4 is **not** available as a Hermes AI provider as of 7.26.0.
Running Ollama + Gemma 4 alongside Hermes + Whisper Tiny + NeuTTS Air on the
A1.Flex's 24 GB RAM was too tight in practice. Gemma 4 remains available for the
daily-progress bot (AI_PROVIDER=gemma4 in Q11).

#### CLIProxyAPI (used by Codex and Claude Code providers)

CLIProxyAPI is a Go binary that listens on `localhost:8317` and exposes your
CLI subscription as an OpenAI-compatible endpoint (`/v1/chat/completions`).
It reads OAuth credentials automatically from their standard locations:

- Codex: `~/.codex/auth.json` (written by `codex login`)
- Claude Code: `~/.claude/.credentials.json` (written by `claude setup-token`)

The `setup-oci-vm-nixos.sh` / `setup-oci-vm.sh` scripts install and start
CLIProxyAPI automatically when you choose either of these providers.
No manual setup is needed beyond the auth capture steps in Q11 / Q9.5.

---

### 3.6. AI プロバイダの選択（日本語）

Hermes は 4 種類の AI バックエンドに対応しています。`/my-harness-init` Q12.6 で選択します。

| プロバイダ | コスト | 認証方式 | 設定 |
|-----------|--------|---------|------|
| **Codex**（ChatGPT Plus/Pro） | 追加費用なし（サブスク利用） | CLIProxyAPI が `~/.codex/auth.json` をラップ | Mac で `codex login` を 1 回実行（Q11） |
| **Claude Code**（Claude Pro/Max） | 追加費用なし（サブスク利用） | CLIProxyAPI が `~/.claude/.credentials.json` をラップ | Mac で `claude setup-token` を 1 回実行（Q9.5） |
| **OpenRouter**（API キー） | 無料枠モデルあり、有料モデルは使用量課金 | 直接接続、`OPENROUTER_API_KEY` 環境変数 | https://openrouter.ai/keys でキーを取得 |
| **Anthropic API**（有料） | トークン従量課金 | 直接接続、`ANTHROPIC_API_KEY` 環境変数 | https://console.anthropic.com/ でキーを取得 |

**推奨:** ChatGPT Plus/Pro または Claude Pro/Max に加入済みの場合は **Codex** または
**Claude Code** を選んでください。サブスクリプションの範囲内で追加費用ゼロで動作します。
CLIProxyAPI が VM のローカル（ポート 8317）で稼働し、既存の CLI OAuth セッションを経由して
リクエストをプロキシします。

**重要:** Gemma 4 は 7.26.0 から Hermes の AI プロバイダとして**利用できません**。
A1.Flex の 24 GB RAM 上で Ollama + Gemma 4 と Hermes + Whisper Tiny + NeuTTS Air を
同時実行すると RAM が不足することが判明しました。Gemma 4 は daily-progress ボット
（Q11 の AI_PROVIDER=gemma4）では引き続き利用可能です。

---

### 4. First-Run Smoke Tests

After `setup-oci-vm-nixos.sh` (or `setup-oci-vm.sh`) completes and `hermes-agent.service` is running:

**Text channel test:**
```
@<YourBotName> hello
```
Hermes should reply within a few seconds.

**Voice message test:**
Record and send a voice message in a Discord text channel.  
The bot transcribes it (local Whisper Tiny) and replies in text + TTS.

**Voice channel test:**
Use the `/join` slash command (or invite the bot with `/voice join`) to have it join a voice channel.  
Speak — it listens, transcribes, calls the AI backend, and speaks the response back via NeuTTS.

### 5. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Bot online but ignores messages | Message Content Intent not enabled | Developer Portal → Bot → Privileged Intents → enable Message Content |
| Bot can't join voice channel | Missing Connect/Speak permissions | Re-generate OAuth URL with Voice permissions (Section 2) |
| `Error: Disallowed intents` in logs | Intents enabled in code but not approved | Developer Portal → Bot → Privileged Intents → toggle all three |
| Voice messages not transcribed | `faster-whisper` not installed | SSH to VM and run `pip install faster-whisper` inside the Hermes venv |
| NeuTTS silent | Model not yet downloaded | First use downloads ~500 MB; allow 5 min on slow links |
| `DISCORD_BOT_TOKEN` error | Token wrong or revoked | Developer Portal → Bot → Reset Token → re-run `bash scripts/ensure-hermes-config.sh <root>` |

### 6. Rotate the Bot Token

If the token leaks (e.g. accidentally committed to git):

1. **Developer Portal** → your application → **Bot** → **Reset Token** → copy new token.
2. On your Mac, run:
   ```bash
   bash scripts/ensure-hermes-config.sh <root> <new-discord-bot-token> <hermes-ai-provider> [<provider-credential>]
   # hermes-ai-provider: codex | claude-code | openrouter | claude-api
   # provider-credential: empty for codex/claude-code; sk-or-... for openrouter; sk-ant-api... for claude-api
   ```
3. Re-run the deploy script to push the updated config:
   ```bash
   bash scripts/setup-oci-vm-nixos.sh <root>   # NixOS path
   # or
   bash scripts/setup-oci-vm.sh <root>          # Oracle Linux path
   ```
4. SSH to the VM and restart Hermes (and CLIProxyAPI if using codex/claude-code):
   ```bash
   sudo systemctl restart cliproxyapi.service   # only if provider=codex or claude-code
   sudo systemctl restart hermes-agent.service
   ```

---

## 日本語

### 1. Discord アプリケーションとボットの作成

1. **https://discord.com/developers/applications** にアクセスしてサインイン。
2. **New Application** をクリック → 名前を入力（例: `Hermes-OCI`）。
3. 左サイドバーの **Bot** をクリック。
4. **Add Bot** → 確認。
5. **Token** の下の **Reset Token** をクリック → トークンをコピー。  
   安全な場所に保存し、`/my-harness-init` Q12.7 に貼り付けるか、`scripts/ensure-hermes-config.sh` に直接渡します。
6. 下にスクロールして **Privileged Gateway Intents** を全て有効化:
   - **Presence Intent**
   - **Server Members Intent**
   - **Message Content Intent** ← Auto Voice Reply に必須
   - **Voice State Intent** はステップ9でボイス権限を追加すると自動付与されます。
7. **Save Changes** をクリック。

### 2. OAuth2 権限の設定（招待 URL）

1. 左サイドバーの **OAuth2** → **URL Generator** をクリック。
2. **Scopes** で以下を選択:
   - `bot`
   - `applications.commands`（`/join` などスラッシュコマンド用）
3. **Bot Permissions** で以下を選択:
   - **テキスト権限:** Send Messages, Read Message History, Add Reactions, Embed Links, Attach Files
   - **ボイス権限:** Connect, Speak, Use Voice Activity
4. ページ下部の生成された URL をコピー。

### 3. ボットをサーバーに招待

1. コピーした OAuth2 URL をブラウザに貼り付け。
2. ドロップダウンから Discord サーバーを選択。
3. **承認** → CAPTCHA を完了。
4. ボットがサーバーのメンバーリストに追加されます（Hermes 起動まではオフライン）。

### 3.5. Hermes が使う 2 つのチャンネルを作成

Hermes は Discord サーバー内で 2 種類のチャンネルを使い分けます:

1. **ホームチャンネル**(例: `#bot-updates`): Hermes が自発的にメッセージを送るチャンネル — 定期タスク出力、リマインダー、日次サマリー、DM 経由で来たボイスメッセージへの返信など。harness は Q12.9 でこの名前を尋ね、`DISCORD_HOME_CHANNEL_NAME` 環境変数として保存します。

2. **アプリケーションチャンネル**(例: `#bot-chat`): ユーザーが @メンション / ボイスチャンネル参加 / DM 経由で Hermes と会話するメインチャンネル。harness は Q12.10 でこの名前を尋ね、`DISCORD_APP_CHANNEL_NAME` 環境変数として保存します(2026-05-14 時点では情報用 — Hermes 自体は現状この値で gate していませんが、将来の Hermes バージョンのために枠を確保しています)。

bot の初回デプロイ**前**に、Discord サーバーで両方のチャンネルを作成してください:

1. Discord サーバーを開く。
2. サイドバーの **テキストチャンネル** 横の `+` をクリック。
3. `bot-updates`(Q12.9 で答える名前)を作成。
4. `bot-chat`(Q12.10 で答える名前)を作成。
5. bot に両チャンネルへの 読取/送信 権限があることを確認(手順 2 の OAuth 招待 URL で自動付与されているはず)。

bot がデプロイされてサーバーに参加すると、環境変数の名前からチャンネルを自動認識します。後から任意のチャンネル内で `/sethome` を実行して上書きすることも可能です(Hermes はチャンネル ID を `config.yaml` に書き込みます — env と yaml の書き込み先に関する [既知の問題 #6447](https://github.com/NousResearch/hermes-agent/issues/6447) も参照)。

### 4. 初回動作確認

`setup-oci-vm-nixos.sh`（または `setup-oci-vm.sh`）が完了し、`hermes-agent.service` が起動したら:

**テキストチャンネルテスト:**
```
@<ボット名> hello
```
数秒以内にボットが応答するはずです。

**音声メッセージテスト:**
Discord のテキストチャンネルで音声メッセージを録音して送信。  
ボットがローカル Whisper Tiny で文字起こしし、テキストと TTS で応答します。

**ボイスチャンネルテスト:**
`/join` スラッシュコマンドでボットをボイスチャンネルに参加させます。  
話しかけると、文字起こし → AI バックエンド → NeuTTS で音声応答が返ってきます。

### 5. トラブルシューティング

| 症状 | 考えられる原因 | 対処法 |
|------|---------------|--------|
| ボットはオンラインだがメッセージを無視する | Message Content Intent が無効 | Developer Portal → Bot → Privileged Intents → Message Content を有効化 |
| ボイスチャンネルに参加できない | Connect/Speak 権限が不足 | ボイス権限を含む OAuth URL を再生成（セクション 2） |
| ログに `Error: Disallowed intents` が出る | コードで有効化したが Portal 未承認 | Developer Portal → Bot → Privileged Intents → 全て有効化 |
| 音声メッセージが文字起こしされない | `faster-whisper` 未インストール | VM に SSH して `pip install faster-whisper` を Hermes venv 内で実行 |
| NeuTTS が無音 | モデル未ダウンロード | 初回使用時に ~500 MB ダウンロード。低速回線では 5 分程度かかります |
| `DISCORD_BOT_TOKEN` エラー | トークンが誤りまたは無効化 | Developer Portal → Bot → Reset Token → `bash scripts/ensure-hermes-config.sh <root>` を再実行 |

### 6. ボットトークンのローテーション

トークンが漏洩した場合（誤って git にコミットした等）:

1. **Developer Portal** → アプリケーション → **Bot** → **Reset Token** → 新しいトークンをコピー。
2. Mac で以下を実行:
   ```bash
   bash scripts/ensure-hermes-config.sh <root> <new-discord-bot-token> <hermes-ai-provider> [<provider-credential>]
   # hermes-ai-provider: codex | claude-code | openrouter | claude-api
   # provider-credential: codex/claude-code は空; openrouter は sk-or-...; claude-api は sk-ant-api...
   ```
3. デプロイスクリプトを再実行してコンフィグを更新:
   ```bash
   bash scripts/setup-oci-vm-nixos.sh <root>   # NixOS パス
   # または
   bash scripts/setup-oci-vm.sh <root>          # Oracle Linux パス
   ```
4. VM に SSH してボットを再起動（codex/claude-code の場合は CLIProxyAPI も）:
   ```bash
   sudo systemctl restart cliproxyapi.service   # provider=codex または claude-code の場合のみ
   sudo systemctl restart hermes-agent.service
   ```
