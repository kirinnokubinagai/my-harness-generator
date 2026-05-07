---
name: harness-resume
description: ハーネス化されたプロジェクトの作業を再開する。`<root>/.my-harness/init-state.json` を読んで current_phase を判定し、適切な次アクション（フェーズ N から再開 / feature 着手 / team-lead 起動 等）を提案・実行する。`/my-harness-init` を中断したり、bootstrap 後に dev/ で新セッションを起こしたときに使う。「resume」「再開」「続きから」等の文脈で発火。
---

# /harness-resume

ハーネス化されたプロジェクトの作業を再開する skill。

## 使う場面

- `/my-harness-init` を途中で中断 → 後で続きから再開したい
- bootstrap 完了後、dev/ で新 Claude Code セッションを起こした → 何から始めればいいか分からない
- 別の人がプロジェクトを引き継いだ → 現状を把握して続きから始めたい

## 動作

### 1. init-state.json を探す

優先順位:

1. `$PWD/.my-harness/init-state.json`（プロジェクトルートで実行）
2. `$PWD/../.my-harness/init-state.json`（dev/ や lanes/feat-xxx/ などの worktree から実行）
3. `$PWD/../../.my-harness/init-state.json`（lanes/feat-xxx/ や深い場所から）

```bash
find_init_state() {
  local d="$PWD"
  for _ in 1 2 3 4 5; do
    if [ -f "$d/.my-harness/init-state.json" ]; then
      echo "$d/.my-harness/init-state.json"
      return 0
    fi
    d=$(dirname "$d")
  done
  return 1
}
```

見つからない場合は「ハーネス化されていません。`/my-harness-init` を実行してください」と案内。

### 2. current_phase に応じて分岐

`init-state.json` の `current_phase` を読み、以下の表で振り分け:

| current_phase | 意味 | 推奨アクション |
|---------------|------|--------------|
| `setup` | Setup フェーズ未完了 | `/my-harness-init` を継続（Setup から） |
| `what` | フェーズ 1 が次 | `/my-harness-init` を継続（フェーズ 1） |
| `platform` | フェーズ 2 が次 | `/my-harness-init` を継続（フェーズ 2） |
| `backend` | フェーズ 3 が次 | `/my-harness-init` を継続（フェーズ 3） |
| `data-model` | フェーズ 4 が次 | `/my-harness-init` を継続（フェーズ 4） |
| `visual` | フェーズ 5 が次 | `/my-harness-init` を継続（フェーズ 5） |
| `bootstrap-completed` | bootstrap 済、issue/task 生成が次 | `/my-harness-init` を継続（フェーズ 6.3） |
| `completed` | 全部完了、実装開始可能 | `/harness-team-lead` または `/harness-new-feature <issue#>` を提案 |

### 3. completed のときの追加チェック

`current_phase=completed` のときは、以下を実行してから提案:

1. **進行中の lane / issue を確認**:
   ```bash
   # lanes/feat-* の状態
   ls "$ROOT"/lanes/ 2>/dev/null

   # GitHub Issue（USE_GITHUB_ISSUES=yes のとき）
   gh issue list --label "lane/1,lane/2,lane/3,lane/4" --state open 2>/dev/null

   # ローカル task ファイル（USE_GITHUB_ISSUES=no のとき）
   ls "$ROOT"/dev/docs/task/child/*.md 2>/dev/null
   ```

2. **進行中があれば**: 「lane=N の issue=#X が in_progress です。続きから？」と提案
3. **無ければ**: 「次の issue を選んで `/harness-new-feature <issue#> <slug>` を実行、または `/harness-team-lead` で全 issue 並列起動」を提案

### 4. Codex auth 切れ rescue があるかチェック

`<root>/.my-harness/codex-auth-rescue/` に保留中の rescue JSON があれば:

```bash
ls "$ROOT"/.my-harness/codex-auth-rescue/*.json 2>/dev/null | head -5
```

→ 「Codex 認証が切れて止まっている作業があります。`codex login` 後に処理を再開しますか？」と提案。

## 出力

ユーザーに以下のサマリーで報告:

```
[harness-resume]
project: <PROJECT_NAME>
root: <root>
current_phase: <phase>
phases_completed: [<list>]
codex_rescue_pending: <count>
suggested_next:
  1. <最も妥当な次アクション>
  2. <代替案>
```

そのうえでユーザーに「上記 1 を実行しますか？」を確認し、yes なら該当コマンドを発火 / 該当 skill を呼ぶ。

## 実装の注意

- 状態は `init-state.json` に書き込まれている前提なので、`/my-harness-init` 等が **必ず init-state.json を更新している** 必要がある（しない skill のバグ）
- `current_phase=completed` でも実装が全部終わっているとは限らない（issue が残っている可能性大）
- ユーザーの意図を汲み取るため、提案を出した後は必ず yes/no を確認してから実行する
