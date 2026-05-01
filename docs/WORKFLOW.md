# 汎用ハーネス 作業フロー

## 役割と並列レーン

team-lead（あなた）が GitHub issue を受け取り、4 レーンに割り振る。各レーンは
analyst-N → engineer-N → e2e-reviewer-N → reviewer-N の順に処理する。

| 役割 | 主責務 |
|------|--------|
| team-lead | issue の振り分け、進捗集約、最終承認 |
| analyst-N | 調査、要件整理、コンフリクトチェック、進捗報告 |
| engineer-N | 実装（コード/インフラ/デザインモック） |
| e2e-reviewer-N | E2E 影響判定 + Playwright/Maestro 実行 |
| reviewer-N | エンジニア規約準拠のコード品質レビュー |

## 標準フロー（1 issue あたり）

1. team-lead が GitHub issue（子）を analyst-N にアサイン。
2. analyst-N が調査し、acceptance criteria を確定 → engineer-N に実装依頼 → team-lead に報告。
3. engineer-N が feature worktree（`/lanes/feat-<issue>/`）で実装、analyst-N に完了報告。
4. analyst-N が e2e 影響を判定:
   - 影響あり → e2e-reviewer-N が Playwright/Maestro 実行
   - 失敗時 → engineer-N に修正依頼（analyst-N 経由）→ team-lead 報告
   - 影響なし、または合格 → reviewer-N へ
5. reviewer-N が規約準拠（変数/JSDoc/Hono Clean Arch/Nix pure 等）をチェック。
   - 不備あり → engineer-N に修正依頼（analyst-N 経由）→ team-lead 報告
6. すべて合格後、husky で pre-commit/pre-push（format/lint/test）を実行し push、PR を dev 向けに作成。
7. analyst-N が team-lead に最終報告。team-lead が結果を集約し次の子 issue へ。

## ブランチとマージ規則

| from → to | 許可条件 |
|-----------|----------|
| feat/* → dev | PR + format/lint/test/typecheck 合格 |
| dev → stage | **人間（あなた）の承認** + OWASP ZAP + Playwright + Maestro + Semgrep + Trivy 合格 |
| stage → main | **人間（あなた）の承認** + 全ゲート緑 |
| hotfix/* → main | 緊急承認 + 最低限の test/lint/format（詳細は HOTFIX.md） |

## コンフリクト方針

- analyst-N は進捗報告を受けるたびに `git fetch origin dev && git merge-base --is-ancestor origin/dev HEAD` 等で衝突可能性を判定。
- 衝突が起きた場合は engineer-N に **マージコミットでの解消** を依頼。
- **`git reset` / `git rebase` / `git push --force` は禁止**。

## 初期化と dev / stage / main の関係

ハーネス導入直後、3 ブランチは同じ「empty initial commit」を共有している。
**stage / main を直接編集することは禁止**（規約 4）なので、
husky / biome / nix flake / GitHub Actions などの **ブートストラップも通常フローで流す**。

具体手順:

1. dev から `feat/bootstrap-harness` worktree を作成（`new-feature.sh` で）。
2. その worktree で husky / biome / nix flake / .github / .harness を導入し PR を dev に作成。
3. CI 緑で dev にマージ → stage / main へは **通常のリリース PR** で順次伝播。
   - dev → stage（OWASP ZAP / E2E 必須）
   - stage → main（人間最終承認 + canary）
4. stage / main の worktree は **マージターゲット（読み取り）として保持** する。
   開発者は基本的に dev とその下の feat ブランチでだけ作業する。

例外:
- hotfix のときだけ main 起点で worktree を作る（`HOTFIX.md` 参照）。

## 進捗報告フォーマット

```
[lane=N issue=#123 phase=engineer→analyst]
status: done|in-progress|blocked
summary: 1〜2 行
artifacts: <PR/commit/file リスト>
next: 次のアクション
risks: コンフリクト可能性 / 影響範囲
```
