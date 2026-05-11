/**
 * 構造化ログ middleware (pino + request-id 伝搬)
 *
 * リクエストごとに request-id を発行し (`x-request-id` ヘッダーがあれば再利用)、
 * `c.set("logger", childLogger)` で下流に渡す。レスポンスにも echo する。
 * 全層 (handler / repository / external client) は `c.get("logger")` を使うこと。
 */

import type { MiddlewareHandler } from "hono";
import pino, { type Logger } from "pino";

const baseLogger = pino({
  level: globalThis.process?.env?.LOG_LEVEL ?? "info",
  base: { service: globalThis.process?.env?.SERVICE_NAME ?? "api" },
  timestamp: pino.stdTimeFunctions.isoTime,
  redact: ["req.headers.authorization", "req.headers.cookie", "*.password"],
});

export type LoggerVars = {
  Variables: {
    logger: Logger;
    requestId: string;
  };
};

/** 32 文字 hex の id を生成 */
function newRequestId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * リクエストロガー middleware
 *
 * 入力ヘッダー `x-request-id` がなければ生成する。
 * 完了時に method / path / status / duration を 1 行で記録する。
 */
export function requestLogger(): MiddlewareHandler<LoggerVars> {
  return async (c, next) => {
    const requestId = c.req.header("x-request-id") ?? newRequestId();
    const child = baseLogger.child({ requestId });
    c.set("logger", child);
    c.set("requestId", requestId);
    c.header("x-request-id", requestId);

    const start = Date.now();
    try {
      await next();
    } finally {
      child.info({
        method: c.req.method,
        path: new URL(c.req.url).pathname,
        status: c.res.status,
        durationMs: Date.now() - start,
      });
    }
  };
}
