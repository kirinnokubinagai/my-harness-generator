# Hermes Agent — Discord Bot Setup Guide

> **Version:** my-harness-generator 7.25.0 | **Date:** 2026-05-14

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
   bash scripts/ensure-hermes-config.sh <root> <new-discord-bot-token> <hermes-ai-provider>
   ```
3. Re-run the deploy script to push the updated config:
   ```bash
   bash scripts/setup-oci-vm-nixos.sh <root>   # NixOS path
   # or
   bash scripts/setup-oci-vm.sh <root>          # Oracle Linux path
   ```
4. SSH to the VM and restart Hermes:
   ```bash
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
   bash scripts/ensure-hermes-config.sh <root> <new-discord-bot-token> <hermes-ai-provider>
   ```
3. デプロイスクリプトを再実行してコンフィグを更新:
   ```bash
   bash scripts/setup-oci-vm-nixos.sh <root>   # NixOS パス
   # または
   bash scripts/setup-oci-vm.sh <root>          # Oracle Linux パス
   ```
4. VM に SSH してボットを再起動:
   ```bash
   sudo systemctl restart hermes-agent.service
   ```
