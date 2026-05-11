# Drizzle / Cloudflare D1

DB stack is Cloudflare D1 + Drizzle ORM. Schema changes go through migrations only.

## Rules

| Item | Rule |
|---|---|
| ORM | Drizzle only |
| DB | Cloudflare D1 (SQLite dialect) |
| Schema change | `drizzle-kit generate --name <descriptive>` |
| Apply migration | `wrangler d1 migrations apply DB --local` / `--remote` |
| `drizzle-kit push` | **Prohibited** — no history, no rollback, no team sharing |
| Manual SQL | Prohibited — schema changes only via schema files |

## Workflow

```bash
# 1. Edit src/db/schema.ts
# 2. Generate (descriptive name required)
"$DEVSH" pnpm exec drizzle-kit generate --name add_users_table
# 3. Apply locally first
"$DEVSH" pnpm exec wrangler d1 migrations apply DB --local
# 4. Apply to staging / production
"$DEVSH" pnpm exec wrangler d1 migrations apply DB --env staging --remote
"$DEVSH" pnpm exec wrangler d1 migrations apply DB --remote
# 5. Commit
git add drizzle/ src/db/schema.ts
git commit -m "feat: add users table migration"
```

## Naming

Good: `add_users_table`, `add_email_index_to_users`, `rename_username_to_display_name`.
Bad: `migration_1`, `update`, `changes`.

## Schema conventions

```ts
import { sqliteTable, text } from 'drizzle-orm/sqlite-core';

// snake_case columns, ULID primary key
export const users = sqliteTable('users', {
  id: text('id').primaryKey(),
  email: text('email').notNull().unique(),
  display_name: text('display_name').notNull(),
  password_hash: text('password_hash').notNull(),
  created_at: text('created_at').notNull(),
  updated_at: text('updated_at').notNull(),
});
// Foreign keys are required:
//   user_id: text('user_id').notNull().references(() => users.id, { onDelete: 'cascade' })
```

## Parallel-development conflict avoidance

Multiple child issues must not generate migrations at the same time. Only one child issue per parent owns the migration work — declare it in the parent issue's body before kicking off the lanes.

## Done

- [ ] After editing `schema.ts`: `drizzle-kit generate --name <descriptive>`
- [ ] `drizzle/*.sql` files staged with `git add`
- [ ] `drizzle-kit push` was not used
- [ ] PR includes both `schema.ts` and `drizzle/` diffs
