---
name: harness-git-discipline
description: Git の rebase / reset --hard / push --force を絶対禁止。コンフリクトはマージコミットで解消。dev / stage / main の保護ブランチで作業しない。「git でコンフリクト」「git reset」「rebase」「force push」等の文脈で発火。
---

# harness-git-discipline

ハーネスのすべての Git 操作で守る規律。

## 鉄則（厳守）

| 操作 | 状態 |
|------|------|
| `git rebase` | **禁止**（interactive 含む） |
| `git rebase --autosquash` | **禁止** |
| `git reset --hard` | **禁止** |
| `git push --force` | **禁止** |
| `git push --force-with-lease` | **禁止**（緩い force push） |
| `git filter-branch` / `filter-repo` | **禁止**（漏洩した secrets の事後消去のみ承認制） |
| **コンフリクト解消** | **必ず `git merge --no-ff` でマージコミットを作る** |

## ブランチ規約

| ブランチ | 用途 | 直接 push |
|----------|------|----------|
| `main` | 本番。stage からのマージのみ | **禁止** |
| `stage` | ステージング。dev からのマージのみ | **禁止** |
| `dev` | 既定の作業統合先。feat ブランチの PR 先 | 通常は禁止（PR 経由） |
| `feat/<issue>-<slug>` | feature 開発、dev 起点 | OK |
| `hotfix/<issue>-<slug>` | 緊急修正、main 起点 | OK |

pre-push フックが main / stage への直接 push を遮断する。

## コンフリクト解消（マージコミットのみ）

```bash
# feature worktree で
cd lanes/feat-123-foo
git fetch origin dev
git merge --no-ff origin/dev -m "merge: resolve with dev (no rebase)"
# コンフリクトを解消（両方の意図を残す）
nix develop --command pnpm exec biome check .
nix develop --command pnpm exec vitest run
git add -A
git commit  # マージコミット完成
git push origin feat/123-foo  # --force 系一切禁止
```

ハーネスのスクリプト:
```bash
bash .my-harness/scripts/resolve-conflict.sh <feature-worktree>
```

## hotfix 後の逆流（main → stage → dev）

すべて `git merge --no-ff` でマージコミット:
```bash
git checkout stage
git merge --no-ff origin/main -m "merge: hotfix back-merge main → stage"
git push origin stage

git checkout dev
git merge --no-ff origin/stage -m "merge: hotfix back-merge stage → dev"
git push origin dev
```

## なぜ rebase / reset 禁止か

- 履歴改変は他者の作業を破壊する
- マージコミットは「いつ」「誰が」「何を」取り込んだかの監査証跡
- 逆流マージで一貫したルール
- 並列開発（4 レーン）で history が壊れない保証

## コミット規約（Conventional Commits）

```
<type>(<scope>): <subject in 日本語>

<body in 日本語>
```

type:
- `feat` / `fix` / `hotfix` / `docs` / `style` / `refactor` / `perf` / `test` / `build` / `ci` / `chore` / `revert`

例:
```
feat(auth): メールアドレスでのログイン機能を追加

bcrypt cost 12 でハッシュ化、JWT は 15 分の短命トークン。
リフレッシュトークンは 7 日。
```

## 履歴に sensitive 情報が入った場合

これは緊急事態。
1. 該当 secret を即座にローテーション（Resend / Cloudflare / GitHub 等）
2. 履歴から消すかは別判断（force push 必要なため別途承認制）
3. gitleaks scheduled scan が定期検出するので未然防止が優先

## チェックリスト

- [ ] `git rebase` を打っていない
- [ ] `git reset --hard` を打っていない
- [ ] `git push --force` / `--force-with-lease` を打っていない
- [ ] コンフリクトはマージコミットで解消
- [ ] main / stage に直接 push していない
- [ ] コミットメッセージが Conventional Commits + 日本語本文
