/**
 * 概要: ユーザー & パスワード再発行トークンの永続化アダプタ (Drizzle D1)。
 *       application 層からはこのファイルの関数だけを呼ぶこと。SQL は外に漏らさない。
 */

import type { D1Database } from '@cloudflare/workers-types';
import { eq } from 'drizzle-orm';
import { createDrizzleClient } from '../../db/client';
import { users, passwordResetTokens } from '../../db/schema';

export type UserRow = typeof users.$inferSelect;
export type ResetTokenRow = typeof passwordResetTokens.$inferSelect;

/** email から user を 1 件取得。存在しなければ null */
export async function findUserByEmail(db: D1Database, email: string): Promise<UserRow | null> {
  const client = createDrizzleClient(db);
  const rows = await client.select().from(users).where(eq(users.email, email)).limit(1);
  return rows[0] ?? null;
}

/** reset token hash から token レコードを取得 */
export async function findUserByResetTokenHash(
  db: D1Database,
  tokenHashHex: string,
): Promise<ResetTokenRow | null> {
  const client = createDrizzleClient(db);
  const rows = await client
    .select()
    .from(passwordResetTokens)
    .where(eq(passwordResetTokens.token_hash_hex, tokenHashHex))
    .limit(1);
  return rows[0] ?? null;
}

/** reset token hash を保存 */
export async function storeResetTokenHash(
  db: D1Database,
  input: { tokenHashHex: string; userId: string; issuedAt: string; expiresAt: string },
): Promise<void> {
  const client = createDrizzleClient(db);
  await client.insert(passwordResetTokens).values({
    token_hash_hex: input.tokenHashHex,
    user_id: input.userId,
    issued_at: input.issuedAt,
    expires_at: input.expiresAt,
    consumed_at: null,
  });
}

/** token を consume + password を更新 (トランザクション相当 — D1 は明示 TX が制限あり) */
export async function consumeResetTokenAndUpdatePassword(
  db: D1Database,
  input: { tokenHashHex: string; userId: string; newPasswordHash: string; consumedAt: string },
): Promise<void> {
  const client = createDrizzleClient(db);
  // D1 は batch でアトミック実行可能
  await db.batch([
    db
      .prepare('UPDATE password_reset_tokens SET consumed_at = ? WHERE token_hash_hex = ?')
      .bind(input.consumedAt, input.tokenHashHex),
    db
      .prepare("UPDATE users SET password_hash = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?")
      .bind(input.newPasswordHash, input.userId),
  ]);
  // client 経由のクエリは型付けされるが、batch は raw API を使う必要がある。
  void client;
}
