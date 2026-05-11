# Multi-Tenant Guide

The default scaffold produced by `/my-harness-init` is **single-tenant**. If
the project needs multi-tenancy (commercial SaaS), follow the steps below to
retrofit. **Earlier is cheaper** — consider this before production launch.

## When to switch to multi-tenant

- B2B SaaS where each customer organization needs isolation
- Data residency requirements (per-customer region pinning)
- Per-customer throughput control (per-tenant rate limiting)
- White-label deployments

Cases where multi-tenant is **not** needed:

- B2C (per-user isolation is enough)
- Internal tools
- Personal projects / validation stage

## Three strategies

| Strategy | DB isolation | Cost | Isolation strength | When to use |
|---|---|---|---|---|
| Shared DB + `tenant_id` column | None | Low | Medium | Tens–hundreds of tenants, low-risk domain |
| Schema isolation | Per-tenant schema in shared DB | Medium | High | Tens of tenants with compliance requirements |
| Full isolation (per-tenant D1) | Complete | High | Strongest | Enterprise, GDPR / HIPAA |

The harness provides retrofit steps assuming **Strategy 1 (shared DB +
`tenant_id`)**. Strategies 2 and 3 are manual.

## Procedure — shared DB + tenant_id

### 1. Add the `tenants` table

```typescript
// Append to dev/src/db/schema.ts
export const tenants = sqliteTable('tenants', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
  created_at: text('created_at').notNull().default(sql`(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))`),
});
```

### 2. Add `tenant_id` to every business table

```typescript
export const users = sqliteTable('users', {
  id: text('id').primaryKey(),
  tenant_id: text('tenant_id').notNull().references(() => tenants.id, { onDelete: 'restrict' }),
  email: text('email').notNull(),
  // ... existing columns
}, (t) => [
  uniqueIndex('uniq_users_tenant_email').on(t.tenant_id, t.email),
  index('idx_users_tenant').on(t.tenant_id),
]);
```

**Note:** the UNIQUE constraint on `email` must become composite
`(tenant_id, email)` so different tenants can register the same email.

### 3. Add a `tid` claim to the JWT

```typescript
// dev/src/application/auth/login.ts
const accessToken = await new SignJWT({ sub: user.id, tid: user.tenant_id })
  .setProtectedHeader({ alg: 'HS256' })
  .setIssuedAt()
  .setExpirationTime(`${ACCESS_TOKEN_TTL_SEC}s`)
  .sign(new TextEncoder().encode(secret));
```

### 4. Add tenant middleware

```typescript
// dev/src/interfaces/http/middleware/tenant.ts
import { jwtVerify } from 'jose';
import type { MiddlewareHandler } from 'hono';

export type TenantVars = { Variables: { tenantId: string; userId: string } };

export function tenantMiddleware(): MiddlewareHandler<TenantVars & { Bindings: { JWT_SECRET: string } }> {
  return async (c, next) => {
    const authz = c.req.header('Authorization');
    if (!authz?.startsWith('Bearer ')) return c.json({ error: 'AUTH_REQUIRED' }, 401);
    const token = authz.slice(7);
    const { payload } = await jwtVerify(token, new TextEncoder().encode(c.env.JWT_SECRET));
    if (typeof payload.tid !== 'string' || typeof payload.sub !== 'string') {
      return c.json({ error: 'AUTH_INVALID' }, 401);
    }
    c.set('tenantId', payload.tid);
    c.set('userId', payload.sub);
    await next();
  };
}
```

### 5. Enforce tenant scoping at the repository layer

```typescript
// dev/src/infrastructure/persistence/post-repository.ts
export async function findPostsByUser(db: D1Database, tenantId: string, userId: string) {
  const client = createDrizzleClient(db);
  return client
    .select()
    .from(posts)
    .where(and(eq(posts.tenant_id, tenantId), eq(posts.user_id, userId)));
}
```

**Rule:** every repository function's second parameter is `tenantId`. To
enforce this, create `rules/multi-tenant.md` and gate reviews on it.

### 6. Convert rate-limit to per-tenant

```typescript
app.use('/api/*', rateLimit({
  bucket: 'api',
  limit: 1000,
  windowSec: 900,
  keyFn: (c) => c.get('tenantId'),
}));
```

### 7. Add tests

At minimum, add these scenarios:

- Cross-tenant access returns 404 (not 403 — never leak existence)
- The same email logs in successfully under two different tenants
- A JWT missing `tid` returns 401

## Extending the audit log

Add `tenant_id` to the `audit_log` table and pass it through `recordAudit()`.
Required when compliance auditors ask "show me tenant X's access history".

## Deletion risk

`tenants.id` is declared `onDelete: 'restrict'` so deleting a tenant does not
cascade-delete its data. For tenant offboarding, build a separate procedure:
**logical delete → physical delete after 30 days** documented in a runbook
(covers GDPR right-to-erasure).

## CI enforcement

Create `rules/multi-tenant.md` so lane agents follow it, and have the
reviewer gate every PR on "is the second argument of every repository
function `tenantId`?". For stronger enforcement, write a custom ESLint rule.
