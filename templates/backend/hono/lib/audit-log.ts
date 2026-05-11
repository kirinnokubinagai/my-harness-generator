/**
 * 監査ログヘルパー
 *
 * 認証 / 権限変更 / データ削除 / 管理操作 / 課金イベントは必ずここに記録する。
 * `rules/production.md` で必須定義。テーブル: `audit_log`。retention ≥ 1 年。
 *
 * append-only。UPDATE / DELETE は禁止 (DB 側のロールで強制すること)。
 */

import { sql } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";

export type AuditAction =
  | "auth.login"
  | "auth.logout"
  | "auth.password_change"
  | "auth.mfa_enabled"
  | "auth.mfa_disabled"
  | "permission.granted"
  | "permission.revoked"
  | "data.deleted"
  | "admin.action"
  | "billing.charge"
  | "billing.refund";

export type AuditEntry = {
  /** 操作主体 (匿名アクセスは "anonymous") */
  actorId: string;
  /** 操作対象 (URN 形式推奨: `user:ulid_xxx` `post:ulid_yyy`) */
  resource: string;
  /** イベント種別 */
  action: AuditAction;
  /** 任意メタデータ (PII はマスク済みで) */
  metadata?: Record<string, unknown>;
  /** 操作元 IP (CF-Connecting-IP) */
  ip?: string;
};

/**
 * 監査ログを記録する
 *
 * @param db - Drizzle D1 インスタンス
 * @param entry - 記録するエントリ
 */
export async function recordAudit(
  db: DrizzleD1Database<Record<string, unknown>>,
  entry: AuditEntry,
): Promise<void> {
  const id = crypto.randomUUID();
  const occurredAt = new Date().toISOString();
  await db.run(sql`
    INSERT INTO audit_log (id, actor_id, action, resource, metadata, ip, occurred_at)
    VALUES (
      ${id},
      ${entry.actorId},
      ${entry.action},
      ${entry.resource},
      ${entry.metadata ? JSON.stringify(entry.metadata) : null},
      ${entry.ip ?? null},
      ${occurredAt}
    )
  `);
}
