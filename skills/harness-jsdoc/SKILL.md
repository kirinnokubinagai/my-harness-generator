---
name: harness-jsdoc
description: JSDoc / TSDoc を全ての変数・定数・関数・型に強制する。関数内コメント禁止、説明文は日本語のみ。「関数を書く」「コメント追加」「型定義」「説明を書く」等の文脈で発火。
---

# harness-jsdoc

ハーネスのコードはすべて **JSDoc / TSDoc 必須**、関数内コメント禁止、**説明はすべて日本語**。

## 鉄則

| 項目 | 規約 |
|------|------|
| 関数 | TSDoc 必須（`@param` `@returns` `@throws` `@example`） |
| 型・クラス・インターフェース | TSDoc 必須 |
| 変数・定数 | JSDoc コメントで意図を説明 |
| **関数内コメント** | **禁止**（説明が必要なら関数を分割） |
| 言語 | **日本語**（固有名詞・型名・コマンド・URL のみ英語可） |

## 関数の書き方

```ts
/**
 * メールアドレスとパスワードからユーザーを作成する。
 *
 * 重複メールチェックは呼び出し前に済んでいることを前提とする。
 * パスワードは bcrypt cost 12 でハッシュ化される。
 *
 * @param input - ユーザー登録に必要な入力（Zod 検証済み）
 * @returns 作成されたユーザー。失敗時は Result.err
 * @throws DatabaseError - DB 接続失敗時
 * @example
 * ```ts
 * const user = await createUser({ email, password, displayName });
 * if (user.isErr()) { ... }
 * ```
 */
export async function createUser(input: CreateUserInput): Promise<Result<User>> {
  // ↑↑↑ コメントなし。すべて TSDoc に書く
}
```

## 変数 / 定数

```ts
/** 最大リトライ回数 */
const MAX_RETRY_COUNT = 3;

/** セッション有効期限（ミリ秒） */
const SESSION_TTL_MS = 3600000;

/** ユーザーの認証状態 */
const isAuthenticated = checkAuth();
```

## 型 / インターフェース

```ts
/**
 * ユーザーリポジトリの契約。
 *
 * 実装は infrastructure 層に置く。domain は実装に依存しない。
 */
export interface UserRepository {
  /** ID で 1 件取得。存在しない場合は null */
  findById(id: UserId): Promise<User | null>;
}
```

## 関数内コメント禁止

```ts
// ❌ ダメ
function process(user: User) {
  // ユーザーをチェック
  if (!user.isActive) return null;
  // 結果を返す
  return user;
}

// ✅ 関数を分けて TSDoc に書く
/**
 * ユーザーがアクティブなら取り出す。非アクティブなら null。
 */
function selectIfActive(user: User): User | null {
  return user.isActive ? user : null;
}
```

## 命名で「自明」を作る

短い名前 + 良い名前で、コメント不要にする:

```ts
// ❌ コメントが必要な命名
const x = users.filter(u => u.a > 0);  // アクティブなユーザー

// ✅ 自明
const activeUsers = users.filter((user) => user.activatedAt !== null);
```

## 日本語必須

| 場所 | 言語 |
|------|------|
| TSDoc 説明 | 日本語 |
| ファイル先頭の概要コメント | 日本語 |
| エラーメッセージ | 日本語（`throw new Error('メールアドレスの形式が正しくありません')`） |
| コミットメッセージ本文 | 日本語（type プレフィックスは英語の Conventional Commits） |
| PR 説明 | 日本語 |
| issue 説明 | 日本語 |
| README / docs | 日本語 |

## チェック

- [ ] 関数 / 型 / 公開定数すべてに TSDoc
- [ ] 関数内コメントが無い
- [ ] 命名で意図が伝わる
- [ ] 説明文がすべて日本語
- [ ] エラーメッセージが日本語
