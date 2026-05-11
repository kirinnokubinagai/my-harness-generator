# Hono Clean Architecture

Strict 4-layer separation. Dependency direction is non-negotiable.

## Layers

```
src/
├── domain/          Entities / value objects / ports (interfaces)
├── application/     Use cases (orchestration only)
├── infrastructure/  Drizzle / Resend / external APIs / Hono handlers
└── interfaces/      Hono routers / DTOs (Zod)
```

## Dependency direction

```
interfaces → application → domain ← infrastructure
```

- `domain/` MUST NOT import from outer layers (Zod is OK).
- `infrastructure/` implements `domain/` interfaces (concrete impls live outside the abstraction).
- `application/` depends on `domain/` only; calls infrastructure through interfaces (DI).
- `interfaces/` calls `application/` only — no business logic in handlers.

## Layer responsibilities

| Layer | Holds |
|---|---|
| domain | Entities, value objects, repository interfaces (`UserRepository` etc.) |
| application | Use cases — one function/class per use case, side effects via DI |
| infrastructure | Drizzle / Resend / R2 / HTTP clients implementing domain interfaces, plus framework code (Hono handlers etc.) |
| interfaces | Hono routers, Zod schemas, DTO conversions |

## Prohibited

- `domain/` importing framework / DB / HTTP packages.
- Business logic inside handlers.
- Repository knowing about application layer.
- `import { db }` directly from `application/` — always go through an interface.

## Example

```ts
// domain/user/user-repository.ts
export interface UserRepository {
  findById(id: UserId): Promise<User | null>;
}

// application/auth/login.ts
export async function login(email: Email, password: string, deps: { userRepo: UserRepository }) { ... }

// infrastructure/persistence/d1-user-repository.ts
export function createD1UserRepository(db: DrizzleClient): UserRepository { ... }

// interfaces/http/auth-router.ts
authRouter.post('/login', zValidator('json', LoginSchema), async (c) => {
  const result = await login(c.req.valid('json').email, c.req.valid('json').password, deps);
  return c.json(result);
});
```

## Done

- [ ] No imports from `domain/` to outer layers (`grep -r "from '../application\|infrastructure\|interfaces'" src/domain/` returns nothing).
- [ ] `application/` does not directly import from `infrastructure/`.
- [ ] `interfaces/` only imports from `application/`.
