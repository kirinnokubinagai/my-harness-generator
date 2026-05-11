# Multi-Tenant Guide

`/my-harness-init` のデフォルトは **single-tenant**。商用 SaaS で multi-tenant
が必要になった場合、この手順で後付けする。**早ければ早いほど安い** ので、
production 投入前に検討すること。

## いつ multi-tenant に切るか

- B2B SaaS で顧客企業ごとに分離が必要
- データ residency 要件 (顧客ごとに region 指定など)
- 顧客ごとの限界スループット制御 (rate-limit の per-tenant 化)
- ホワイトラベル展開

逆に **不要なケース**:
- B2C (ユーザー単位の分離で十分)
- 内部用ツール
- 個人プロジェクト / 検証段階

## 戦略 3 種

| 戦略 | DB 分離 | コスト | 隔離強度 | 推奨ケース |
|---|---|---|---|---|
| 共有 DB + `tenant_id` 列 | なし | 低 | 中 | 数十〜数百テナント、低リスク領域 |
| Schema 分離 | DB 内 schema | 中 | 高 | 数十テナント、コンプライアンス要件あり |
| 完全分離 (テナント別 D1) | 完全 | 高 | 最強 | エンタープライズ、GDPR / HIPAA |

harness は **戦略 1 (共有 DB + `tenant_id`)** を想定した後付け手順を提供する。
戦略 2/3 は手動。

## 手順 — 共有 DB + tenant_id

### 1. tenants テーブル追加

```typescript
// dev/src/db/schema.ts に追記
export const tenants = sqliteTable('tenants', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
  created_at: text('created_at').notNull().default(sql`(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))`),
});
```

### 2. 全業務テーブルに `tenant_id` を追加

```typescript
export const users = sqliteTable('users', {
  id: text('id').primaryKey(),
  tenant_id: text('tenant_id').notNull().references(() => tenants.id, { onDelete: 'restrict' }),
  email: text('email').notNull(),
  // ... 既存列
}, (t) => [
  uniqueIndex('uniq_users_tenant_email').on(t.tenant_id, t.email),
  index('idx_users_tenant').on(t.tenant_id),
]);
```

**注意:** `email` の UNIQUE 制約は `(tenant_id, email)` の複合に変える。
別テナントで同じ email を許容するため。

### 3. JWT に `tid` claim を入れる

```typescript
// dev/src/application/auth/login.ts
const accessToken = await new SignJWT({ sub: user.id, tid: user.tenant_id })
  .setProtectedHeader({ alg: 'HS256' })
  .setIssuedAt()
  .setExpirationTime(`${ACCESS_TOKEN_TTL_SEC}s`)
  .sign(new TextEncoder().encode(secret));
```

### 4. tenant middleware を追加

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

### 5. Repository に tenant scoping を強制

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

**ルール:** すべての repository 関数の第 2 引数を `tenantId` にする。
これを徹底するため `rules/multi-tenant.md` を作成して enforce する。

### 6. rate-limit を per-tenant に

```typescript
app.use('/api/*', rateLimit({
  bucket: 'api',
  limit: 1000,
  windowSec: 900,
  keyFn: (c) => c.get('tenantId'),
}));
```

### 7. テストを増やす

最低限、以下のシナリオを追加する:

- 別テナントのデータを叩こうとすると 404 を返すこと (403 ではなく — 存在自体を漏らさない)
- 同一 email + 別テナントで両方ログインできること
- tenant_id 欠落の JWT で 401 になること

## 監査ログの拡張

`audit_log` テーブルにも `tenant_id` を追加し、`recordAudit()` から渡す。
コンプライアンス監査で「テナント X のアクセス履歴を出せ」と言われた時に必要。

## 削除リスク

`tenants.id` を `onDelete: 'restrict'` にしているのは、テナント削除でデータが
連鎖削除されないため。テナント解約時は別途 **論理削除 → 30 日後物理削除**
の手順を runbook 化する (GDPR の削除権対応含む)。

## CI チェック追加

`rules/multi-tenant.md` を作って lane エージェントに守らせ、reviewer が
「全 repository 関数の第 2 引数が tenantId か」を確認する gate にする。
さらに静的解析を入れる場合は ESLint のカスタムルールで強制可。
