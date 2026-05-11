/**
 * レート制限 middleware (Hono + Workers KV)
 *
 * トークンバケット方式。バインド KV を使用するので Cloudflare Workers 専用。
 * Cloudflare Rate Limiting binding が利用可能ならそちらが優先。
 *
 * 既定値は `rules/production.md`:
 *   ログイン       5 / 15 min / IP+account
 *   パスワード再発行 3 / hour / email
 *   API 認証あり    100 / 15 min / IP
 *   API 認証なし    30  / 15 min / IP
 */

import type { MiddlewareHandler } from "hono";

type RateLimitEnv = {
  RATE_LIMIT_KV: KVNamespace;
};

export type RateLimitOptions = {
  /** KV キーの名前空間 (例: "login", "password-reset") */
  bucket: string;
  /** 許可リクエスト数 */
  limit: number;
  /** ウィンドウ秒数 */
  windowSec: number;
  /** クライアント識別子の抽出 (省略時は IP) */
  keyFn?: (c: Parameters<MiddlewareHandler>[0]) => string;
};

/** クライアント IP を CF-Connecting-IP / X-Forwarded-For から取得 */
function clientIp(c: Parameters<MiddlewareHandler>[0]): string {
  return (
    c.req.header("CF-Connecting-IP") ??
    c.req.header("X-Forwarded-For")?.split(",")[0]?.trim() ??
    "unknown"
  );
}

/**
 * レート制限 middleware を生成する
 *
 * @param options - バケット名 / 上限 / ウィンドウ秒
 */
export function rateLimit(options: RateLimitOptions): MiddlewareHandler<{
  Bindings: RateLimitEnv;
}> {
  const { bucket, limit, windowSec, keyFn = clientIp } = options;
  return async (c, next) => {
    const id = keyFn(c);
    const key = `rl:${bucket}:${id}`;
    const now = Math.floor(Date.now() / 1000);
    const windowStart = now - (now % windowSec);

    const raw = await c.env.RATE_LIMIT_KV.get(key);
    const state: { window: number; count: number } = raw
      ? JSON.parse(raw)
      : { window: windowStart, count: 0 };

    if (state.window !== windowStart) {
      state.window = windowStart;
      state.count = 0;
    }

    if (state.count >= limit) {
      const reset = windowStart + windowSec;
      c.header("Retry-After", String(reset - now));
      c.header("X-RateLimit-Limit", String(limit));
      c.header("X-RateLimit-Remaining", "0");
      c.header("X-RateLimit-Reset", String(reset));
      return c.json(
        {
          success: false,
          error: {
            code: "RATE_LIMIT_EXCEEDED",
            message: "リクエストが多すぎます。しばらく待ってから再度お試しください",
          },
        },
        429,
      );
    }

    state.count += 1;
    await c.env.RATE_LIMIT_KV.put(key, JSON.stringify(state), {
      expirationTtl: windowSec * 2,
    });

    c.header("X-RateLimit-Limit", String(limit));
    c.header("X-RateLimit-Remaining", String(limit - state.count));
    c.header("X-RateLimit-Reset", String(windowStart + windowSec));
    await next();
  };
}
