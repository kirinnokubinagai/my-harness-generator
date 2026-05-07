---
name: harness-jsdoc
description: Requires JSDoc / TSDoc on every variable, constant, function, and type. Prohibits inline comments inside function bodies. All descriptions must be written in the project language (PROJECT_LANG from .my-harness/.config, default en). Fires when the user says "write a function", "add a comment", "type definition", "write a description", or similar.
---

# harness-jsdoc

All code in the harness requires **JSDoc / TSDoc**. Inline comments inside function bodies are prohibited. **All descriptions must be written in `$PROJECT_LANG`** (read from `<root>/.my-harness/.config`, default: `en`).

```bash
PROJECT_LANG=$(grep -E "^PROJECT_LANG=" "$ROOT/.my-harness/.config" 2>/dev/null | cut -d= -f2)
PROJECT_LANG="${PROJECT_LANG:-en}"
```

## Non-negotiable rules

| Item | Rule |
|------|------|
| Functions | TSDoc required (`@param`, `@returns`, `@throws`, `@example`) |
| Types / classes / interfaces | TSDoc required |
| Variables / constants | Explain intent with a JSDoc comment |
| **Inline comments in function bodies** | **Prohibited** (split the function if you need to explain it) |
| Language | **`$PROJECT_LANG`** (proper nouns, type names, commands, and URLs may be in English) |

## How to write functions

When `PROJECT_LANG=en`:
```ts
/**
 * Creates a user from an email address and password.
 *
 * Assumes duplicate email check is done before calling.
 * Password is hashed with bcrypt cost 12.
 *
 * @param input - Input required for user registration (Zod-validated)
 * @returns The created user. On failure, Result.err
 * @throws DatabaseError - On DB connection failure
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

When `PROJECT_LANG=ja`:
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
 */
export async function createUser(input: CreateUserInput): Promise<Result<User>> {
  // No inline comments. Everything goes in the TSDoc above.
}
```

## Variables / constants

When `PROJECT_LANG=en`:
```ts
/** Maximum retry count */
const MAX_RETRY_COUNT = 3;

/** Session TTL in milliseconds */
const SESSION_TTL_MS = 3600000;

/** User authentication state */
const isAuthenticated = checkAuth();
```

When `PROJECT_LANG=ja`:
```ts
/** 最大リトライ回数 */
const MAX_RETRY_COUNT = 3;

/** セッション有効期限（ミリ秒） */
const SESSION_TTL_MS = 3600000;

/** ユーザーの認証状態 */
const isAuthenticated = checkAuth();
```

## Types / interfaces

When `PROJECT_LANG=en`:
```ts
/**
 * Contract for the user repository.
 *
 * Implementation lives in the infrastructure layer. Domain does not depend on the implementation.
 */
export interface UserRepository {
  /** Fetch a single record by ID. Returns null if not found. */
  findById(id: UserId): Promise<User | null>;
}
```

## Inline comments are prohibited

```ts
// ❌ Bad
function process(user: User) {
  // check user
  if (!user.isActive) return null;
  // return result
  return user;
}

// ✅ Good — split the function and put everything in TSDoc
/**
 * Returns the user if active, null if inactive.
 */
function selectIfActive(user: User): User | null {
  return user.isActive ? user : null;
}
```

## Make intent obvious through naming

Good names eliminate the need for comments:

```ts
// ❌ Needs a comment to be understood
const x = users.filter(u => u.a > 0);  // active users

// ✅ Self-explanatory
const activeUsers = users.filter((user) => user.activatedAt !== null);
```

## Language conventions by PROJECT_LANG

| Location | en | ja |
|----------|----|----|
| TSDoc descriptions | English | Japanese |
| File-level summary comments | English | Japanese |
| Error messages | English (e.g. `throw new Error('Invalid email format')`) | Japanese (e.g. `throw new Error('メールアドレスの形式が正しくありません')`) |
| Commit message body | English | Japanese (type prefix follows English Conventional Commits) |
| PR descriptions | English | Japanese |
| Issue descriptions | English | Japanese |
| README / docs | English | Japanese |

## Checklist

- [ ] All functions / types / public constants have TSDoc
- [ ] No inline comments inside function bodies
- [ ] Names convey intent without comments
- [ ] All descriptions are in `$PROJECT_LANG`
- [ ] Error messages are in `$PROJECT_LANG`
