---
name: harness-drizzle-rules
description: Drizzle ORM + Cloudflare D1 の規約を強制する。drizzle-kit migrate のみ使用、push 禁止、マイグレーションの命名・順序を保証。「DB スキーマを変更」「マイグレーション」「テーブル追加」等の文脈で発火。
---

# harness-drizzle-rules

DB は **Cloudflare D1 + Drizzle ORM** のみ。スキーマ変更は **マイグレーション経由のみ**。

## 鉄則

| 項目 | 規約 |
|------|------|
| ORM | Drizzle のみ（他 ORM は使わない） |
| DB | Cloudflare D1（SQLite ダイアレクト） |
| スキーマ変更 | 必ず `drizzle-kit generate --name <具体名>` でマイグレーション生成 |
| マイグレーション適用 | `wrangler d1 migrations apply DB --local` / `--remote` |
| **`drizzle-kit push` 禁止** | 履歴・ロールバック・チーム共有不能 |
| 手動 SQL | 禁止。スキーマファイル経由でしか変更しない |

## ワークフロー

```bash
# 1. src/db/schema.ts を編集
# 2. マイグレーション生成（具体名必須）
nix develop --command pnpm exec drizzle-kit generate --name add_users_table

# 3. ローカル適用（初回は必須）
nix develop --command pnpm exec wrangler d1 migrations apply DB --local

# 4. 本番 / stage 適用
nix develop --command pnpm exec wrangler d1 migrations apply DB --remote
nix develop --command pnpm exec wrangler d1 migrations apply DB --env staging --remote

# 5. コミット
git add drizzle/ src/db/schema.ts
git commit -m "feat: add users table migration"
```

## マイグレーション命名

| 良い例 | 悪い例 |
|--------|--------|
| `add_users_table` | `migration_1` |
| `add_email_index_to_users` | `update` |
| `rename_username_to_display_name` | `changes` |

## スキーマ規約

```ts
import { sqliteTable, text, integer } from 'drizzle-orm/sqlite-core';

// snake_case のカラム名、ULID 主キー
export const users = sqliteTable('users', {
  id: text('id').primaryKey(),
  email: text('email').notNull().unique(),
  display_name: text('display_name').notNull(),
  password_hash: text('password_hash').notNull(),
  created_at: text('created_at').notNull(),
  updated_at: text('updated_at').notNull(),
});
```

外部キー必須:
```ts
user_id: text('user_id').notNull().references(() => users.id, { onDelete: 'cascade' })
```

## なぜ push 禁止か

| 機能 | migrate | push |
|------|---------|------|
| 履歴 | ✅ 残る | ❌ |
| ロールバック | ✅ | ❌ |
| チーム共有 | ✅ | ❌ |
| 本番安全 | ✅ | ❌ |
| Git 管理 | ✅ | ❌ |

## マイグレーション衝突防止（並列開発）

複数子 issue が同時にマイグレーションを生成しないこと。`harness-team-lead` agent が `check-migration-conflict.sh` で検出する。1 親 issue 配下で **マイグレーション担当の子 issue は 1 つに集約**。

## チェック

- [ ] schema.ts を編集後、`drizzle-kit generate --name <具体名>` 実行済
- [ ] drizzle/ 配下の SQL を git add 済
- [ ] `drizzle-kit push` を **使っていない**
- [ ] PR に schema.ts と drizzle/ の差分が同梱
