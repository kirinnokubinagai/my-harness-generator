---
name: harness-jsdoc
description: Requires JSDoc / TSDoc on every variable, constant, function, and type. Prohibits inline comments inside function bodies. All descriptions must be written in Japanese (the generated project's default output language convention). Fires when the user says "write a function", "add a comment", "type definition", "write a description", or similar.
---

# harness-jsdoc

All code in the harness requires **JSDoc / TSDoc**. Inline comments inside function bodies are prohibited. **All descriptions must be written in Japanese** (this is the generated project's default output language convention).

## Non-negotiable rules

| Item | Rule |
|------|------|
| Functions | TSDoc required (`@param`, `@returns`, `@throws`, `@example`) |
| Types / classes / interfaces | TSDoc required |
| Variables / constants | Explain intent with a JSDoc comment |
| **Inline comments in function bodies** | **Prohibited** (split the function if you need to explain it) |
| Language | **Japanese** (proper nouns, type names, commands, and URLs may be in English) |

## How to write functions

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
  // No inline comments. Everything goes in the TSDoc above.
}
```

## Variables / constants

```ts
/** 最大リトライ回数 */
const MAX_RETRY_COUNT = 3;

/** セッション有効期限（ミリ秒） */
const SESSION_TTL_MS = 3600000;

/** ユーザーの認証状態 */
const isAuthenticated = checkAuth();
```

## Types / interfaces

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

## Inline comments are prohibited

```ts
// ❌ Bad
function process(user: User) {
  // ユーザーをチェック
  if (!user.isActive) return null;
  // 結果を返す
  return user;
}

// ✅ Good — split the function and put everything in TSDoc
/**
 * ユーザーがアクティブなら取り出す。非アクティブなら null。
 */
function selectIfActive(user: User): User | null {
  return user.isActive ? user : null;
}
```

## Make intent obvious through naming

Good names eliminate the need for comments:

```ts
// ❌ Needs a comment to be understood
const x = users.filter(u => u.a > 0);  // アクティブなユーザー

// ✅ Self-explanatory
const activeUsers = users.filter((user) => user.activatedAt !== null);
```

## Japanese is required (generated project's default language convention)

| Location | Language |
|----------|----------|
| TSDoc descriptions | Japanese |
| File-level summary comments | Japanese |
| Error messages | Japanese (e.g. `throw new Error('メールアドレスの形式が正しくありません')`) |
| Commit message body | Japanese (type prefix follows English Conventional Commits) |
| PR descriptions | Japanese |
| Issue descriptions | Japanese |
| README / docs | Japanese |

## Checklist

- [ ] All functions / types / public constants have TSDoc
- [ ] No inline comments inside function bodies
- [ ] Names convey intent without comments
- [ ] All descriptions are in Japanese
- [ ] Error messages are in Japanese
