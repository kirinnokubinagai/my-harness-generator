---
name: harness-tdd
description: テスト駆動開発（TDD）を強制する。新機能実装、バグ修正、リファクタリング、振る舞い変更の前に必ず適用。Red-Green-Refactor のサイクルを守り、テスト無しで本番コードを書かないことを保証する。「テストを書いて」「TDD で」「実装する前に」「バグを直す」等の文脈で発火。
---

# harness-tdd

ハーネス配下のすべての本番コード変更で適用する TDD ルール。

## 鉄則

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.
```

テスト無しで本番コードを書いた場合は **コードを削除して書き直す**。例外無し。

## サイクル

### RED（失敗テスト）
1 つの振る舞いだけをテストする失敗ケースを書く。
- テスト名は「〜できること」「〜になること」（日本語）
- AAA パターン（Arrange / Act / Assert をコメントで明示）
- モックは外部依存のみ。Real code を直接呼ぶ。

### Verify RED（必須）
```bash
nix develop --command pnpm exec vitest related --run <test>
```
- 期待する理由で失敗していることを確認（typo ではない）
- パスしてしまう場合 → テストが既存挙動を見ている。テストを直す。

### GREEN（最小実装）
テストを通す **最小限のコード**。YAGNI 厳守。

### Verify GREEN
```bash
nix develop --command pnpm exec vitest run
```
他のテストも全部緑なら次へ。

### REFACTOR
緑のまま:
- 命名改善
- 関数分割
- JSDoc/TSDoc 追加（`harness-jsdoc` skill 参照）

新しい振る舞いは追加しない。

## E2E TDD

UI / API 公開面の変更は Playwright（Web）または Maestro（Mobile）で同じサイクル:
1. 失敗 E2E を書く
2. 「実装が無いから赤」を確認
3. 実装
4. 緑

## 禁止パターン

- テスト後付け
- `it.skip` / `test.todo` の濫用
- 「動作確認しました」だけで進める
- console.log デバッグ残置
- 1 テストに複数の Assert（独立性）

## ハーネス内コマンド

```bash
nix develop --command pnpm exec vitest run                  # 全テスト
nix develop --command pnpm exec vitest related --run <f>    # 関連のみ
nix develop --command pnpm exec playwright test             # Web E2E
nix develop --command maestro test tests/e2e/mobile         # Mobile E2E
```

## 完了条件

- [ ] 各新規関数 / メソッドに対応するテストがある
- [ ] 各テストの失敗を実際に目視した
- [ ] 最小実装で緑にした
- [ ] biome / tsc / vitest すべて緑
- [ ] 出力に warning / error 無し
