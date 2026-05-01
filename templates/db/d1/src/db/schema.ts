/**
 * 概要: Cloudflare D1（SQLite）用の Drizzle スキーマ定義。
 *       スキーマ変更後は必ず `pnpm db:generate --name <具体名>` でマイグレーションを生成し、
 *       drizzle/ 配下の SQL ファイルをコミットする。`drizzle-kit push` は使用禁止。
 */

import { sqliteTable, text } from 'drizzle-orm/sqlite-core';
import { sql } from 'drizzle-orm';

/**
 * users テーブル。ULID 主キーで時系列ソートを可能にする。
 */
export const users = sqliteTable('users', {
  id: text('id').primaryKey(),
  email: text('email').notNull().unique(),
  display_name: text('display_name').notNull(),
  password_hash: text('password_hash').notNull(),
  created_at: text('created_at').notNull().default(sql`(datetime('now'))`),
  updated_at: text('updated_at').notNull().default(sql`(datetime('now'))`),
});

/**
 * password_reset_tokens テーブル。平文トークンは保存せず、SHA-256 ハッシュのみ保管する。
 */
export const passwordResetTokens = sqliteTable('password_reset_tokens', {
  token_hash_hex: text('token_hash_hex').primaryKey(),
  user_id: text('user_id')
    .notNull()
    .references(() => users.id, { onDelete: 'cascade' }),
  issued_at: text('issued_at').notNull(),
  expires_at: text('expires_at').notNull(),
  consumed_at: text('consumed_at'),
});
