# JSDoc / TSDoc

All exports require TSDoc. Inline comments inside function bodies are prohibited. Descriptions are written in `$LANG` (read from `.my-harness/.config`, default `en`).

## Rules

| Item | Requirement |
|---|---|
| Functions | TSDoc required (`@param`, `@returns`, `@throws`, `@example` as needed) |
| Types / classes / interfaces | TSDoc required |
| Variables / constants | One-line JSDoc explaining intent |
| Inline comments in function bodies | **Prohibited** — split the function instead |
| Language | `$LANG` (proper nouns, type names, commands, URLs may stay English) |

## Functions

`$LANG=en`:
```ts
/**
 * Creates a user from email and password.
 *
 * Duplicate-email check must be done by the caller.
 * Password is hashed with bcrypt cost 12.
 *
 * @param input - Validated registration input
 * @returns The created user, or Result.err on failure
 * @throws DatabaseError - On DB connection failure
 */
export async function createUser(input: CreateUserInput): Promise<Result<User>> { ... }
```

`$LANG=ja`:
```ts
/**
 * メールアドレスとパスワードからユーザーを作成する。
 *
 * 重複メールチェックは呼び出し前に済んでいることを前提とする。
 * パスワードは bcrypt cost 12 でハッシュ化される。
 */
export async function createUser(input: CreateUserInput): Promise<Result<User>> { ... }
```

## Variables / constants

```ts
/** Maximum retry count */
const MAX_RETRY_COUNT = 3;

/** Session TTL in milliseconds */
const SESSION_TTL_MS = 3600000;
```

## Inline comments are prohibited

```ts
// ❌
function process(user: User) {
  // check user
  if (!user.isActive) return null;
  return user;
}

// ✅ Split and document via TSDoc
/** Returns the user if active, null otherwise. */
function selectIfActive(user: User): User | null {
  return user.isActive ? user : null;
}
```

## Naming over comments

```ts
// ❌
const x = users.filter(u => u.a > 0);  // active users
// ✅
const activeUsers = users.filter((user) => user.activatedAt !== null);
```

## Language matrix

| Location | en | ja |
|---|---|---|
| TSDoc | English | 日本語 |
| Error messages | English | 日本語 |
| Commit body / PR / issue | English | 日本語 |
| README / docs | English | 日本語 |
| Type names / commit prefix | English | English |
