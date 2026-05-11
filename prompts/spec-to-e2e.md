# Spec → Playwright E2E プロンプト

以下の機能仕様から Playwright E2E テストを 1 つの `.spec.ts` ファイルとして生成してください。

## 機能タイトル

{{FEATURE_TITLE}}

## 機能仕様

{{FEATURE_BODY}}

## 出力要件

1. **形式** — TypeScript、Playwright `test()` API、`@playwright/test` を使用
2. **テストケース数** — happy path 1 件 + sad path 2 件以上
3. **セレクタ優先順** — `data-testid` > role-based (`getByRole`) > text-based (`getByText`)。XPath / CSS class は禁止
4. **API 直接呼び出し禁止** — 実 backend を UI 経由で叩く。`page.route()` で API モックも禁止 (stage 環境前提)
5. **assertion はユーザー観点** — 「URL が変わる」「特定のテキストが表示される」「button が disabled になる」「toast が表示される」。内部状態を直接 assert しない
6. **認証フロー** — `import { login } from './fixtures/auth'` を使う前提でよい。fixture が無ければ TODO コメントで明示
7. **テスト命名** — `「<前提>のとき<操作>すると<結果>になること」` 形式 (`rules/testing.md`)
8. **ヘッダー** — ファイル冒頭に `/** 概要: ... */` JSDoc コメント (`rules/jsdoc.md`)

## 出力形式

`.spec.ts` の本文だけを出力してください。前置き / 説明文 / マークダウン code fence は不要です。
