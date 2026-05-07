---
name: harness-drizzle-rules
description: Enforces Drizzle ORM + Cloudflare D1 conventions. Only drizzle-kit migrate is allowed; push is prohibited; migration naming and ordering are guaranteed. Fires when the user mentions "change DB schema", "migration", "add a table", or similar.
---

# harness-drizzle-rules

The DB stack is **Cloudflare D1 + Drizzle ORM** exclusively. Schema changes must go through **migrations only**.

## Non-negotiable rules

| Item | Rule |
|------|------|
| ORM | Drizzle only (no other ORMs) |
| DB | Cloudflare D1 (SQLite dialect) |
| Schema changes | Always generate via `drizzle-kit generate --name <descriptive-name>` |
| Applying migrations | `wrangler d1 migrations apply DB --local` / `--remote` |
| **`drizzle-kit push` is prohibited** | Cannot produce history, rollbacks, or team-shareable state |
| Manual SQL | Prohibited — schema changes only through schema files |

## Workflow

```bash
# 1. Edit src/db/schema.ts
# 2. Generate migration (descriptive name required)
nix develop --command pnpm exec drizzle-kit generate --name add_users_table

# 3. Apply locally (required on first run)
nix develop --command pnpm exec wrangler d1 migrations apply DB --local

# 4. Apply to production / stage
nix develop --command pnpm exec wrangler d1 migrations apply DB --remote
nix develop --command pnpm exec wrangler d1 migrations apply DB --env staging --remote

# 5. Commit
git add drizzle/ src/db/schema.ts
git commit -m "feat: add users table migration"
```

## Migration naming

| Good | Bad |
|------|-----|
| `add_users_table` | `migration_1` |
| `add_email_index_to_users` | `update` |
| `rename_username_to_display_name` | `changes` |

## Schema conventions

```ts
import { sqliteTable, text, integer } from 'drizzle-orm/sqlite-core';

// snake_case column names, ULID primary key
export const users = sqliteTable('users', {
  id: text('id').primaryKey(),
  email: text('email').notNull().unique(),
  display_name: text('display_name').notNull(),
  password_hash: text('password_hash').notNull(),
  created_at: text('created_at').notNull(),
  updated_at: text('updated_at').notNull(),
});
```

Foreign keys are required:
```ts
user_id: text('user_id').notNull().references(() => users.id, { onDelete: 'cascade' })
```

## Why push is prohibited

| Feature | migrate | push |
|---------|---------|------|
| History | ✅ Preserved | ❌ |
| Rollback | ✅ | ❌ |
| Team sharing | ✅ | ❌ |
| Production safety | ✅ | ❌ |
| Git-managed | ✅ | ❌ |

## Preventing migration conflicts (parallel development)

Multiple child issues must not generate migrations at the same time. The `harness-team-lead` agent detects conflicts via `check-migration-conflict.sh`. **Only one child issue per parent issue should own the migration work.**

## Checklist

- [ ] After editing schema.ts, ran `drizzle-kit generate --name <descriptive-name>`
- [ ] SQL files under `drizzle/` are staged with git add
- [ ] `drizzle-kit push` was **not used**
- [ ] PR includes diffs for both schema.ts and drizzle/
