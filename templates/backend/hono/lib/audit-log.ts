/**
 * 監査ログヘルパー
 *
 * 認証 / 権限変更 / データ削除 / 管理操作 / 課金イベントを必ず記録する。
 * `rules/production.md` で必須定義。append-only テーブル `audit_log`。retention ≥ 1 年。
 *
 * DB 抽象化: アダプタインターフェース `AuditWriter` を介して操作するので、
 * D1 / Postgres / MySQL / SQLite いずれの Drizzle 実装にも差し替え可能。
 */

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

/** DB に 1 レコード書き込む最小契約。実装は DB 種別ごとに差し替え可能 */
export type AuditWriter = (row: {
  id: string;
  actorId: string;
  action: string;
  resource: string;
  metadata: string | null;
  ip: string | null;
  occurredAt: string;
}) => Promise<void>;

/**
 * 監査ログを記録する
 *
 * @param write - DB アダプタ (`drizzleD1AuditWriter` などで生成)
 * @param entry - 記録するエントリ
 */
export async function recordAudit(write: AuditWriter, entry: AuditEntry): Promise<void> {
  await write({
    id: crypto.randomUUID(),
    actorId: entry.actorId,
    action: entry.action,
    resource: entry.resource,
    metadata: entry.metadata ? JSON.stringify(entry.metadata) : null,
    ip: entry.ip ?? null,
    occurredAt: new Date().toISOString(),
  });
}

// ───────── 既製アダプタ ─────────
// Drizzle のジェネリック型 `AnyDatabase` に依存するのを避けるため、
// 各アダプタは「db.run(sql\`...\`)` を持つ最小インターフェース」を要求する。

type SqlRunner = {
  run: (query: unknown) => Promise<unknown>;
};

/**
 * Drizzle D1 / SQLite / Postgres / MySQL いずれにも対応するアダプタを生成する。
 * `sql` テンプレートタグはユーザー側から渡してもらう (drizzle-orm から import)。
 */
export function drizzleAuditWriter(
  db: SqlRunner,
  sqlTag: (strings: TemplateStringsArray, ...values: unknown[]) => unknown,
): AuditWriter {
  return async (row) => {
    await db.run(sqlTag`
      INSERT INTO audit_log (id, actor_id, action, resource, metadata, ip, occurred_at)
      VALUES (
        ${row.id},
        ${row.actorId},
        ${row.action},
        ${row.resource},
        ${row.metadata},
        ${row.ip},
        ${row.occurredAt}
      )
    `);
  };
}
