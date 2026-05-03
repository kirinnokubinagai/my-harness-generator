---
name: harness-nix-pure
description: Nix flake による完全 pure な環境を強制する。impure な実行（brew install / グローバル npm 等）を禁止。direnv による自動 shell 起動を必須化。「コマンドを実行」「ツールをインストール」「環境構築」等の文脈で発火。
---

# harness-nix-pure

ハーネス配下のすべてのツール実行は **Nix flake 経由のみ**。何も入っていない PC で `direnv allow` 一発で完全再現可能であることを保証する。

## 鉄則

| 項目 | 規約 |
|------|------|
| ツール実行 | `nix develop --command ...` 経由のみ |
| 自動化 | `.envrc` に `use flake` を書き、`direnv allow` で自動切替 |
| 例外 | Apple toolchain（Xcode / iOS Simulator）と Claude Code / Codex CLI のみ |
| 禁止 | `brew install` / グローバル `npm install -g` / システム `pip install` |

## 推奨フロー（プロジェクトに入る）

```bash
cd <project>/dev
direnv allow                          # 初回のみ
# 以降、cd するだけで flake.nix の dev shell に自動切替
node --version                        # nix の Node.js が使われる
pnpm --version                        # nix の pnpm
```

direnv 未インストール時:
```bash
nix develop                           # 手動で flake shell に入る
# シェルを抜けても作業継続したい場合は `nix develop --command <cmd>`
```

## 標準コマンド（必ず prefix を付ける）

```bash
nix develop --command pnpm install
nix develop --command pnpm exec biome check .
nix develop --command pnpm exec vitest run
nix develop --command pnpm exec tsc --noEmit
nix develop --command pnpm exec wrangler d1 migrations apply DB --local
nix develop --command pnpm exec playwright test
nix develop --command maestro test tests/e2e/mobile
nix develop --command terraform apply
nix develop --command sops -d secrets/cloudflare.enc.json
```

## 禁止パターン

- `brew install pnpm` / `brew install nodejs`
- `npm install -g <anything>`
- `pip install --user <anything>`
- `curl ... | bash` でツール導入
- システムの Python / Ruby / Go を直接利用

## flake.nix 更新時

```bash
# flake.nix を編集後、必ず flake.lock もコミット
git add flake.nix flake.lock .envrc
direnv reload   # 自動で nix develop が再評価される
```

## CI でも同じ規約

GitHub Actions では:
```yaml
- uses: DeterminateSystems/nix-installer-action@v18
- run: nix develop --command pnpm install
- run: nix develop --command pnpm exec vitest run
```

## 例外（Apple / Claude Code / Codex）

- iOS Simulator は Xcode 依存、Nix 化不可（`docs/IOS_DAST.md` 参照）
- Android SDK の platform-tools / build-tools は Google 配布で Nix 化困難
- Claude Code（このエージェント）と Codex CLI（`@openai/codex`）は対話 AI なので例外

## チェック

- [ ] `.envrc` に `use flake` がある
- [ ] `direnv allow` 実行済（or `nix develop` で shell に入っている）
- [ ] `command -v node | grep nix/store` で Nix の node が使われている
- [ ] CI が `nix develop --command` で動作
