# `dev/secrets/` — SOPS-encrypted secrets

このディレクトリには **age 公開鍵で暗号化された** secrets ファイルだけを置く。
平文 `.env` を置いてはいけない (`rules/no-hardcoded-secrets.md`)。

## 初回セットアップ (1 度だけ)

```bash
# 1. age 鍵ペアを生成
nix develop --command age-keygen -o ~/.age/key.txt
# 公開鍵を表示 (これを .sops.yaml に貼る)
nix develop --command age-keygen -y ~/.age/key.txt

# 2. .sops.yaml の `age:` セクションに公開鍵を追記
#    チームメンバーは各自の公開鍵を append する

# 3. SOPS_AGE_KEY_FILE を export
echo 'export SOPS_AGE_KEY_FILE=$HOME/.age/key.txt' >> ~/.bashrc  # or zshrc/fish

# 4. 暗号化ファイルを作成
nix develop --command sops --encrypt --output secrets/dev.enc.json - <<'EOF'
{
  "DATABASE_URL": "postgresql://...",
  "RESEND_API_KEY": "re_..."
}
EOF
```

## 復号 (アプリ起動時)

```bash
nix develop --command sops --decrypt secrets/dev.enc.json | jq -r 'to_entries|.[]|"export \(.key)=\(.value)"' | source /dev/stdin
```

`scripts/load-secrets.sh` がこの操作をラップしている (リポジトリに含まれる場合)。

## CI

GitHub Actions は `AGE_SECRET_KEY_STAGE` シークレットを使って復号する
(`docs/SETUP.md` 参照)。

## ファイル命名規約

| ファイル | 用途 |
|---|---|
| `secrets/dev.enc.json`     | dev 環境 |
| `secrets/stage.enc.json`   | stage 環境 |
| `secrets/prod.enc.json`    | prod 環境 — 触れるのは ops + デプロイ実行者のみ |

`.sops.yaml` の `creation_rules` が `secrets/*.enc.json` をマッチしている。
