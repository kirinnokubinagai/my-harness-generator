# daily-progress-bot — Claude が 18:00 にチームへ進捗報告

Oracle Cloud Always-Free VM 上で Claude Pro/Max subscription を使って、
毎日 18:00 (JST) に GitHub の活動を要約 → Discord に投稿します。

- **追加コスト: 0 円** (既存の Claude Pro/Max + Oracle Cloud Always Free + Discord 無料 plan)
- **時刻精度: 数秒以内** (= cron + 専用 VM、GitHub Actions の ~15 分遅延問題なし)
- **Anthropic 公式に許可された使い方** ([Pro/Max で Claude Code を CI/cron で使う](https://support.claude.com/en/articles/11145838))

## 全体構成

```
[GitHub Repo]
   ↓ gh CLI (read-only PAT)
[OCI VM ARM Ampere A1 / Always Free]
   └ cron 09:00 UTC = 18:00 JST
      ├ daily-progress.sh が GitHub 活動を収集
      ├ claude -p ... で Claude (sonnet-4-6) が要約
      └ curl -X POST で Discord webhook へ
[Discord channel]
```

## 1 回だけのセットアップ手順

### Step 1 — Oracle Cloud Always Free VM を作る

1. [Oracle Cloud](https://www.oracle.com/cloud/free/) に無料アカウント作成 (要クレカ確認、課金はされない)
2. Console → Compute → Instances → Create Instance
3. **Shape**: VM.Standard.A1.Flex (Ampere ARM)、1 OCPU + 6 GB RAM くらいで十分
4. **Image**: Canonical Ubuntu 22.04 LTS (ARM 版)
5. SSH 公開鍵を登録 → Create
6. パブリック IP が割り当てられたら ssh で入る: `ssh opc@<public-ip>` (Oracle Linux なら `opc`、Ubuntu なら `ubuntu`)

### Step 2 — VM 上で依存をインストール

```bash
# Node.js LTS + 必要ツール
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash -
sudo apt-get install -y nodejs jq curl gh

# Claude Code CLI
npm config set prefix '~/.npm-global'
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
. ~/.bashrc
npm install -g @anthropic-ai/claude-code

# 確認
claude --version
gh --version
jq --version
```

### Step 3 — Claude にログイン (= OAuth トークン取得)

VM はブラウザがないので、**手元の Mac/PC で 1 回ログインしてトークンをコピーする**:

```bash
# 手元のマシン
claude login              # ブラウザで OAuth 認証
cat ~/.claude/.credentials.json | jq -r '.access_token'
# → コピーする
```

このトークンを VM の `.env` に貼る (Step 4 で)。

### Step 4 — bot のファイル配置

```bash
# VM 上で
mkdir -p ~/daily-progress-bot
cd ~/daily-progress-bot
```

`daily-progress.sh` と `.env.example` を VM に転送 (`scp` などで):

```bash
# 手元のマシンから
scp daily-progress.sh .env.example crontab.example opc@<vm-ip>:~/daily-progress-bot/
```

VM 上で `.env` を作る:

```bash
cd ~/daily-progress-bot
cp .env.example .env
nano .env             # 値を埋める
chmod 600 .env        # 必須 (= world-readable で漏れないように)
chmod +x daily-progress.sh
```

### Step 5 — 試運転

```bash
cd ~/daily-progress-bot
./daily-progress.sh
# → Discord channel に投稿が来ることを確認
```

### Step 6 — cron に登録

```bash
crontab -e
# crontab.example の最終行をコピー
# 0 9 * * * /home/opc/daily-progress-bot/daily-progress.sh >> /home/opc/daily-progress-bot/cron.log 2>&1
```

UTC 09:00 = JST 18:00。OCI VM はデフォルト UTC なのでこれで OK。

### Step 7 — 翌日 18:00 に通知が来るか確認

来なければ `cat ~/daily-progress-bot/cron.log` で原因確認。

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| `claude CLI not on PATH` | `~/.bashrc` の `PATH=~/.npm-global/bin:$PATH` を確認、`source ~/.bashrc` |
| Discord に何も来ない | `bash daily-progress.sh` を VM 上で直接実行してエラー確認、webhook URL の `chmod 600 .env` 後の値確認 |
| Claude が要約を返さない | OAuth トークン期限切れ (~90 日)。手元で `claude login` 再実行、トークン更新、`.env` に貼り直し |
| 早朝の cron が走らない | OCI VM が default Stopped 状態だと cron も止まる。Instance Pool で Always Running 維持 |
| `gh api` で 401 | `GH_TOKEN` の PAT が期限切れ or scope 不足。`contents:read`, `issues:read`, `actions:read` 必要 |

## OAuth トークン rotate

Claude Pro/Max の OAuth トークンは **約 90 日で期限切れ**します。
切れたら bot が静かに失敗 (Discord に投稿来ない)。 手元で `claude login`
を再実行 → 新トークンを `.env` に貼り直し → `chmod 600 .env` で復旧。

長期運用するなら 80 日ごとにカレンダーリマインダー推奨。

## 規約上の留意点

Anthropic 公式の Consumer ToS でこの使い方は明示的に許可されています:

> Claude Code CLI running on your own computer is Anthropic's official product
> built for scripted and automated use, and the Consumer ToS exempts it from
> the prohibition on automated access.

ただし `one human, one subscription, one beneficiary` 原則:
- ✅ 自分の Pro/Max を自分の repo の自分のための通知に使う
- ❌ 同じトークンで複数人の作業を要約 / 配信、外部顧客向けサービスとして提供

チームで使うなら Anthropic **Team Plan** に切り替えてください。

## なぜ GitHub Actions ではなく OCI VM か

GitHub Actions の cron は:
- ~15 分遅延が標準 ([GitHub 公式 docs](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule))
- 正時 (= "0 H * * *") は更に混んで遅延 ([同じく公式に「正時を避けろ」と記述](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule))
- 60 日 inactive で workflow が自動 disable される
- fork で scheduled workflow が disable される

OCI VM の cron は専用 scheduler なので **数秒精度** + 上記の制約が無い。

## 削除する場合

OCI Console → Instance → Terminate。Always Free なので削除しても課金リスク無し。
