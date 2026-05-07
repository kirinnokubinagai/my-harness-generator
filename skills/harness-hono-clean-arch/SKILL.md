---
name: harness-hono-clean-arch
description: Enforces Clean Architecture on Hono backends. Mandates 4-layer separation (domain / application / infrastructure / interfaces) and strict dependency direction rules. Fires when the user says "write a Hono API", "add a handler", "implement a use case", "write a repository", or similar.
---

# harness-hono-clean-arch

Applies Clean Architecture **strictly** to Hono applications.

## 4-layer structure

```
src/
├── domain/          Entities / value objects / ports (interfaces)
├── application/     Use cases (orchestration)
├── infrastructure/  Drizzle implementations / external APIs / Resend / Hono handlers
└── interfaces/      Hono routers / input-output DTOs (Zod)
```

## Dependency direction (non-negotiable)

```
interfaces → application → domain ← infrastructure
```

- **domain must not depend on outer layers** (pure business rules only)
- **infrastructure implements domain interfaces** (concrete implementations live outside; abstractions live inside)
- application uses domain and calls infrastructure through interfaces
- interfaces only call application (no business logic inside)

## Layer responsibilities

### domain
- Entities / value objects
- Repository interfaces (`UserRepository`, etc.)
- Zero external dependencies (minimal npm deps; Zod is OK)

### application
- One use case = one function / class
- Encodes "what to do"; delegates "how to do it" through interfaces
- Side effects received via dependency injection

### infrastructure
- Concrete implementations of Drizzle / Resend / R2 / external HTTP
- Implements domain repository interfaces
- Framework code (Hono handlers, etc.) lives here

### interfaces
- Hono routers
- Zod schemas (input validation)
- DTO transformations

## Prohibited patterns

- domain importing framework, DB, or HTTP dependencies
- Business logic inside handlers
- Repository knowing about application layer
- `import { db }` directly from application (must always go through an interface)

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

## Checklist

- [ ] No imports from domain/ to outer layers (verifiable with grep)
- [ ] application/ does not directly import from infrastructure/
- [ ] interfaces/ only imports from application/
