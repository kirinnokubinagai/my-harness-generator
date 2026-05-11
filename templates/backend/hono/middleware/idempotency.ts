/**
 * 冪等性 middleware (`Idempotency-Key` ヘッダー対応)
 *
 * POST / PUT / PATCH / DELETE のうち `Idempotency-Key` ヘッダーが付いたものは、
 * 同一キーでの再送に対してキャッシュ済みレスポンスを返す。24h TTL。KV 必須。
 *
 * 仕様: https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/
 */

import type { MiddlewareHandler } from "hono";

type IdempotencyEnv = {
  IDEMPOTENCY_KV: KVNamespace;
};

const STATE_CHANGING = new Set(["POST", "PUT", "PATCH", "DELETE"]);
/** TTL: 24 時間 */
const TTL_SECONDS = 60 * 60 * 24;

export function idempotency(): MiddlewareHandler<{
  Bindings: IdempotencyEnv;
}> {
  return async (c, next) => {
    if (!STATE_CHANGING.has(c.req.method)) return next();

    const key = c.req.header("Idempotency-Key");
    if (!key) return next();

    if (key.length < 8 || key.length > 128) {
      return c.json(
        {
          success: false,
          error: {
            code: "INVALID_IDEMPOTENCY_KEY",
            message: "Idempotency-Key は 8〜128 文字で指定してください",
          },
        },
        400,
      );
    }

    const cacheKey = `idem:${c.req.method}:${new URL(c.req.url).pathname}:${key}`;
    const cached = await c.env.IDEMPOTENCY_KV.get(cacheKey);
    if (cached) {
      const { status, body, headers } = JSON.parse(cached) as {
        status: number;
        body: unknown;
        headers: Record<string, string>;
      };
      for (const [k, v] of Object.entries(headers)) c.header(k, v);
      c.header("Idempotent-Replay", "true");
      return c.json(body, status as 200);
    }

    await next();

    const status = c.res.status;
    if (status >= 200 && status < 300) {
      const cloned = c.res.clone();
      const body = await cloned.json().catch(() => null);
      const headers: Record<string, string> = {};
      cloned.headers.forEach((v, k) => {
        headers[k] = v;
      });
      await c.env.IDEMPOTENCY_KV.put(
        cacheKey,
        JSON.stringify({ status, body, headers }),
        { expirationTtl: TTL_SECONDS },
      );
    }
  };
}
