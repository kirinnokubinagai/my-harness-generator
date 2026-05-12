# Notifications & Daily-Progress Bot — Setup Walkthrough

This guide walks you through every external account you may need for the optional
notification + Oracle Cloud daily-progress bot offered by `/my-harness-init`.

Each section is bilingual: **日本語 (Japanese) first**, then **English**.

You do **not** need every section — only the one(s) `/my-harness-init` asked you
to consult. Use the section index below.

| # | Section | Required when … |
|---|---------|-----------------|
| 1 | Discord webhook | Q6 = Discord |
| 2 | Slack webhook | Q6 = Slack |
| 3 | Microsoft Teams webhook | Q6 = Teams |
| 4 | GitHub fine-grained PAT | Q8 (always, when notifications enabled) |
| 5 | Oracle Cloud (OCI) account + API key | Q9 = Yes (provision now) |

---

## 1. Discord — Webhook URL

### 日本語

#### Step 1 — アカウントを作る（無料）

1. ブラウザで <https://discord.com/register> を開く。
2. メールアドレス・ユーザー名・パスワード・生年月日を入力して登録。
3. 認証メールのリンクをクリックして本人確認を完了する。

クレジットカードは不要。完全に無料。

#### Step 2 — サーバーを作る（既にあれば飛ばす）

1. 左サイドバーの **「+」** ボタン → **「オリジナルの作成」** → **「自分と友達のため」**。
2. サーバー名を入力（例: `my-project-notifications`）→ **「作成」**。

#### Step 3 — Webhook を作成する

1. Webhook を送りたいチャンネル（例: `#general`）の横にカーソルを合わせ、
   歯車アイコン **「チャンネルの編集」** をクリック。
2. 左メニューから **「連携サービス」** を選択。
3. **「ウェブフック」** → **「新しいウェブフック」**。
4. 名前（例: `my-harness-bot`）を設定し、 **「ウェブフック URL をコピー」** をクリック。
5. URL は `https://discord.com/api/webhooks/<数字>/<トークン>` の形式。
   **このトークン部分は秘密**（漏れたら誰でも投稿できる）。

#### Step 4 — `/my-harness-init` に戻り URL を貼り付ける

戻ったセッションで「Paste」を選んで、コピーした URL を貼り付ければ完了。

### English

#### Step 1 — Create an account (free)

1. Open <https://discord.com/register>.
2. Enter email / username / password / DOB and sign up.
3. Click the verification link in the confirmation email.

No credit card required. Completely free.

#### Step 2 — Create a server (skip if you already have one)

1. Click the **+** button in the left sidebar → **Create My Own** → **For me and my friends**.
2. Pick a name (e.g. `my-project-notifications`) → **Create**.

#### Step 3 — Create the webhook

1. Hover the channel you want notifications in (e.g. `#general`) → gear icon
   **Edit Channel**.
2. Left menu → **Integrations**.
3. **Webhooks** → **New Webhook**.
4. Name it (e.g. `my-harness-bot`), click **Copy Webhook URL**.
5. The URL looks like `https://discord.com/api/webhooks/<id>/<token>`.
   **The token is a secret** — anyone with it can post to your channel.

#### Step 4 — Return to `/my-harness-init` and paste

Pick **Paste** on the next prompt and paste the URL you copied.

---

## 2. Slack — Incoming Webhook URL

### 日本語

#### Step 1 — Slack ワークスペースを作る・参加する

1. <https://slack.com/get-started> から無料ワークスペースを作成 or 既存に参加。
2. メールアドレスとパスワードで登録。クレジットカード不要。

#### Step 2 — Slack App を作成する

1. <https://api.slack.com/apps> を開き **「Create New App」** → **「From scratch」**。
2. App 名（例: `my-harness-bot`）と対象ワークスペースを選択 → **「Create App」**。

#### Step 3 — Incoming Webhook を有効化する

1. 左メニュー **「Incoming Webhooks」**。
2. **「Activate Incoming Webhooks」** を **On** に切り替え。
3. 下にスクロール → **「Add New Webhook to Workspace」**。
4. 投稿先チャンネル（例: `#general`）を選び **「Allow」**。
5. 発行された URL（`https://hooks.slack.com/services/T.../B.../xxx`）をコピー。

#### Step 4 — `/my-harness-init` に戻り貼り付ける

「Paste」を選んで貼り付け。

### English

#### Step 1 — Sign up / join a Slack workspace

1. Create a free workspace at <https://slack.com/get-started> or join an existing one.
2. Email + password registration. No credit card.

#### Step 2 — Create a Slack App

1. Go to <https://api.slack.com/apps> → **Create New App** → **From scratch**.
2. App name (e.g. `my-harness-bot`) + workspace → **Create App**.

#### Step 3 — Enable Incoming Webhooks

1. Left menu → **Incoming Webhooks**.
2. Toggle **Activate Incoming Webhooks** to **On**.
3. Scroll down → **Add New Webhook to Workspace**.
4. Pick the destination channel (e.g. `#general`) → **Allow**.
5. Copy the URL (`https://hooks.slack.com/services/T.../B.../xxx`).

#### Step 4 — Return to `/my-harness-init` and paste

Choose **Paste** and paste the URL.

---

## 3. Microsoft Teams — Incoming Webhook

### 日本語

#### Step 1 — Teams アカウントを用意

1. <https://www.microsoft.com/microsoft-teams/free> から無料版にサインアップ
   （Microsoft アカウントが必要）、または既存の組織アカウントを使用。

#### Step 2 — チームとチャンネルを用意

1. Teams 左サイドバー **「チーム」** → **「チームに参加 / チームを作成」**。
2. 対象チャンネル（無ければ作成）の横の **「⋯」** → **「コネクタ」**。
   *（組織ポリシーでコネクタが無効化されている場合は IT 管理者に有効化を依頼）*

#### Step 3 — Incoming Webhook を追加する

1. **「Incoming Webhook」** を探し **「構成」**。
2. 名前（例: `my-harness-bot`）を入力、必要ならアイコン画像をアップロード。
3. **「作成」** → 発行された URL をコピー → **「完了」**。
4. URL は `https://<tenant>.webhook.office.com/...` の形式。

#### Step 4 — `/my-harness-init` に戻り貼り付ける

「Paste」を選んで貼り付け。

### English

#### Step 1 — Get a Teams account

1. Sign up free at <https://www.microsoft.com/microsoft-teams/free> with a
   Microsoft account, or use your existing org account.

#### Step 2 — Pick a team and channel

1. In Teams, left sidebar → **Teams** → **Join or create a team**.
2. Next to your channel (or create one), click **⋯** → **Connectors**.
   *(If Connectors are disabled by org policy, ask your IT admin to enable them.)*

#### Step 3 — Add an Incoming Webhook

1. Find **Incoming Webhook** → **Configure**.
2. Name it (e.g. `my-harness-bot`), optionally upload an icon.
3. Click **Create** → copy the URL → **Done**.
4. URL looks like `https://<tenant>.webhook.office.com/...`.

#### Step 4 — Return to `/my-harness-init` and paste

Choose **Paste** and paste the URL.

---

## 4. GitHub — Fine-grained Personal Access Token (PAT)

The OCI VM's daily-progress bot uses this PAT (read-only) to query open issues,
PRs, and recent workflow runs via `gh`.

### 日本語

#### Step 1 — GitHub にサインインする

<https://github.com/login> でログイン。アカウントが無ければ無料で作成。

#### Step 2 — Fine-grained PAT を作成する

1. プロフィール画像 → **「Settings」** → 一番下 **「Developer settings」**。
2. **「Personal access tokens」** → **「Fine-grained tokens」** → **「Generate new token」**。
3. 入力内容:
   - **Token name**: 例 `my-harness-progress-bot`
   - **Expiration**: 90 日（推奨。期限切れたら作り直す）
   - **Repository access**:
     - 単一プロジェクトのみ → **「Only select repositories」** で対象 repo を選択
     - 全 repo を見せたい場合 → **「All repositories」**
   - **Repository permissions**（**すべて Read-only**）:
     - **Contents**: Read-only
     - **Issues**: Read-only
     - **Pull requests**: Read-only
     - **Actions**: Read-only
   - 他の権限は触らない（書き込み権限を付けない）。
4. **「Generate token」** → 表示された `github_pat_...` をコピー。
   **この画面を閉じると二度と表示されない**ので即コピー。

#### Step 3 — `/my-harness-init` に貼り付ける

戻って「Paste」を選び PAT を貼る。

#### セキュリティ注意

- **PAT を git にコミットしない**。`.my-harness/.notification.env` は自動で
  `.gitignore` に追加される。
- 漏洩した場合は即 GitHub Settings → Developer settings → Revoke。

### English

#### Step 1 — Sign in to GitHub

Log in at <https://github.com/login>. Sign up free if needed.

#### Step 2 — Create the fine-grained PAT

1. Profile picture → **Settings** → bottom of left nav **Developer settings**.
2. **Personal access tokens** → **Fine-grained tokens** → **Generate new token**.
3. Fill in:
   - **Token name**: e.g. `my-harness-progress-bot`
   - **Expiration**: 90 days (recommended — regenerate when it expires)
   - **Repository access**:
     - Single project → **Only select repositories**, pick your repo
     - All repos → **All repositories**
   - **Repository permissions** (**all Read-only**):
     - **Contents**: Read-only
     - **Issues**: Read-only
     - **Pull requests**: Read-only
     - **Actions**: Read-only
   - Leave every other permission alone. Do NOT grant write access.
4. Click **Generate token** → copy the `github_pat_...` string.
   **It is shown only once** — copy it immediately.

#### Step 3 — Paste into `/my-harness-init`

Return to the session, choose **Paste**, paste the token.

#### Security notes

- **Never commit the PAT to git.** The skill writes it to
  `.my-harness/.notification.env`, which is auto-added to `.gitignore`.
- If it leaks, revoke immediately at GitHub Settings → Developer settings.

---

## 5. Oracle Cloud (OCI) — Always-Free VM + API key

The bot runs on a free Ampere A1 VM (4 OCPU / 24 GB RAM, always-free tier).
You set up the OCI account + API key once; the script provisions and configures
the VM end-to-end.

### 日本語

#### Step 1 — Oracle Cloud アカウントを作成する

1. <https://cloud.oracle.com> を開く → **「無料で始める」**。
2. メール・氏名・住所・電話番号を入力。
3. **クレジットカードの登録が必須**（無料枠を使う場合でも本人確認のため）。
   - 課金は発生しない（Always-Free リソースのみを使うため）。
   - ただし誤って有料リソースを作るとカードに請求されるので注意。
4. SMS で電話番号を認証。
5. 確認メール経由でログイン完了。
6. **ホームリージョン** を選ぶ画面が出る — このリージョンは**後から変更不可**。
   - 日本なら `Japan East (Tokyo)` または `Japan Central (Osaka)` を推奨。
   - A1 容量切れの地域もあるため、複数地域を試せる柔軟性が欲しければ
     `US East (Ashburn)` を選ぶのも一案。

#### Step 2 — OCI CLI 認証用 API キーを生成する

1. OCI Console 右上のプロフィールアイコン → **「ユーザー設定」**。
2. 左メニュー **「APIキー」** → **「APIキーの追加」**。
3. **「APIキー・ペアの生成」** を選択 → **「秘密キーのダウンロード」** と
   **「公開キーのダウンロード」** をクリック。
4. ダウンロードした秘密キーを `~/.oci/oci_api_key.pem` に保存:

   ```bash
   mkdir -p ~/.oci
   mv ~/Downloads/<your-key-name>.pem ~/.oci/oci_api_key.pem
   chmod 600 ~/.oci/oci_api_key.pem    # ← 必須
   ```

   **`chmod 600` は必須**。これより緩い権限だと OCI CLI が秘密キーを拒否する。

5. **「追加」** をクリック → 表示される **「構成ファイルプレビュー」** を全部コピー。
   `[DEFAULT]` セクションが既に整形されている。

#### Step 3 — `~/.oci/config` を保存する

```bash
mkdir -p ~/.oci
cat > ~/.oci/config <<'EOF'
[DEFAULT]
user=ocid1.user.oc1..xxxxxxxx
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..xxxxxxxx
region=ap-osaka-1
key_file=~/.oci/oci_api_key.pem
EOF
chmod 600 ~/.oci/config
```

`key_file` を `~/.oci/oci_api_key.pem` に書き換えるのを忘れない（プレビューには
別パスが書かれている）。

#### Step 4 — `/my-harness-init` に戻る

`oci` CLI（`nix develop` 経由で自動的にインストールされる）が `~/.oci/config`
を見つけて検証する。VM 名 / リージョン / SSH 鍵ファイル名を聞かれたら答える
だけ。スクリプトが残りを全て自動化する（VCN 作成、サブネット選択、AD ローテー
ション、`ssh-keygen`、`cloud-init` 配信）。

#### セキュリティ注意

- **`~/.oci/oci_api_key.pem` を絶対に git にコミットしない**。ホームディレクト
  リの外に出さない。漏洩したら即 OCI Console → User Settings → API Keys から
  当該キーを削除すれば無効化できる。
- **`chmod 600 ~/.oci/oci_api_key.pem` と `chmod 600 ~/.oci/config`** は必須。
- A1 Always-Free 容量は人気で「Out of Host Capacity」が頻発する。スクリプト
  は AD を 3 つまで自動リトライするが、それでも失敗したら時間を置くか別リー
  ジョンに切り替える。

### English

#### Step 1 — Create an Oracle Cloud account

1. Open <https://cloud.oracle.com> → **Sign up for free**.
2. Provide email, name, address, phone.
3. **A credit card is required** (identity verification, even for free-tier use).
   - You will not be billed if you only use Always-Free resources.
   - Be careful — accidentally creating paid resources will charge the card.
4. Verify phone via SMS.
5. Confirm email → log in.
6. The wizard asks you to pick a **home region**, which is **permanent** —
   you cannot change it later.
   - Japan users: `Japan East (Tokyo)` or `Japan Central (Osaka)`.
   - For broader capacity flexibility, `US East (Ashburn)` historically has
     more A1 capacity.

#### Step 2 — Generate an API signing key

1. In the OCI Console, profile icon (top-right) → **User settings**.
2. Left nav → **API keys** → **Add API key**.
3. Pick **Generate API Key Pair** → click **Download Private Key** and
   **Download Public Key**.
4. Move the private key to `~/.oci/oci_api_key.pem`:

   ```bash
   mkdir -p ~/.oci
   mv ~/Downloads/<your-key>.pem ~/.oci/oci_api_key.pem
   chmod 600 ~/.oci/oci_api_key.pem    # ← REQUIRED
   ```

   **`chmod 600` is mandatory.** Looser permissions cause the OCI CLI to refuse
   to read the key.

5. Click **Add** → copy the entire **Configuration File Preview** shown
   afterwards. It contains a pre-formatted `[DEFAULT]` section.

#### Step 3 — Save `~/.oci/config`

```bash
mkdir -p ~/.oci
cat > ~/.oci/config <<'EOF'
[DEFAULT]
user=ocid1.user.oc1..xxxxxxxx
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..xxxxxxxx
region=ap-osaka-1
key_file=~/.oci/oci_api_key.pem
EOF
chmod 600 ~/.oci/config
```

Remember to rewrite `key_file` to point at `~/.oci/oci_api_key.pem` (the
preview lists a different default path).

#### Step 4 — Return to `/my-harness-init`

The `oci` CLI (installed via `nix develop`) will find `~/.oci/config` and
validate it. Answer the VM name / region / SSH key filename prompts and the
script handles the rest (VCN creation, subnet selection, AD rotation,
`ssh-keygen`, `cloud-init` payload).

#### Security notes

- **Never commit `~/.oci/oci_api_key.pem` to git.** Keep it strictly inside
  your home directory. If it leaks, immediately delete the corresponding key
  in OCI Console → User Settings → API Keys.
- **`chmod 600 ~/.oci/oci_api_key.pem` and `chmod 600 ~/.oci/config`** are
  mandatory.
- A1 Always-Free capacity is popular and "Out of Host Capacity" errors are
  common. The script auto-retries up to 3 availability domains; if it still
  fails, wait a few hours or pick another region.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `ensure-notification-webhook.sh` exits 2 | URL shape mismatch | Recopy from the source UI — extra spaces / newlines break the regex |
| `ensure-github-pat.sh` exits 2 | PAT shape mismatch | Ensure you generated a fine-grained (`github_pat_...`) or classic (`ghp_...`) PAT, not an OAuth token |
| `ensure-oci-vm.sh` exits 1 (`~/.oci/config not found`) | Step 3 not done | Re-do section 5 step 3 above |
| `ensure-oci-vm.sh` exits 2 (`Out of Host Capacity`) | Free-tier A1 region exhausted | Wait an hour and re-run, or pick another region |
| `oci` CLI complains about permissions | `~/.oci/oci_api_key.pem` is too open | `chmod 600 ~/.oci/oci_api_key.pem` |

---

## Where the secrets live

After all four scripts have run successfully:

```
<project-root>/.my-harness/
├── .notification.env     # service + webhook URL + GH_TOKEN (chmod 600, gitignored)
└── .oci-vm.env           # VM OCID, public IP, SSH key path (chmod 600, gitignored)
```

The `.notification.env` file is never committed. `.gitignore` already covers
`.my-harness/.notification.env` and `.my-harness/.oci-vm.env`.
