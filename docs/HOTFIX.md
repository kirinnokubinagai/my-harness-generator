# Hotfix ワークフロー（質問9への回答）

## 基本方針

通常フローは feat → dev → stage → main だが、本番事故の緊急修正は時間制約上この順を踏めない。
以下の **限定的な例外フロー** を採用する。

## フロー

1. **issue 起票**: `hotfix/` ラベルを付け、親 issue を作らず単独で作成。SLA は 24 時間。
2. **worktree 作成**: `main` から派生。
   ```bash
   git worktree add lanes/hotfix-<issue> -b hotfix/<issue> main
   ```
3. **修正 + 最小テスト**: 影響範囲を最小化、新規機能追加は厳禁。pre-commit / pre-push の husky は必須。
4. **PR 1: hotfix/<issue> → main**
   - 人間（あなた）の緊急承認が必要
   - 通過ゲート: format / lint / unit test / typecheck / Trivy
   - OWASP ZAP / E2E は **post-merge 即時実施**（ブロッキングしない代わりに、不合格時は即ロールバック）
5. **逆流マージ（rebase 禁止、必ずマージコミット）**:
   ```bash
   # main → stage
   git checkout stage && git merge --no-ff main
   # stage → dev
   git checkout dev && git merge --no-ff stage
   ```
6. **post-mortem**: 24 時間以内に親 issue を作成し、再発防止策を子 issue で展開。

## 通常フローとの差分

| 項目 | 通常 | Hotfix |
|------|------|--------|
| 起点ブランチ | dev | main |
| PR 先 | dev | main |
| stage 経由 | 必須 | スキップ可（緊急時） |
| ZAP/E2E | pre-merge | post-merge 即時 |
| 親/子 issue | 必須 | post-mortem で事後作成 |

## 禁止事項

- `git reset --hard`, `git rebase`, `git push --force`, `--force-with-lease` も原則禁止。
- main を直接編集しない（必ず hotfix ブランチを切る）。
- 逆流をスキップしない（dev/stage に修正が含まれないと再発する）。
