/**
 * 概要: 構造化リクエストロガー (pino + request-id 伝搬)。
 *       `x-request-id` ヘッダーがあれば再利用し、無ければ 32 文字 hex を生成。
 *       下流層は `c.get('logger')` で child logger を受け取り、全ログ行に
 *       request-id をスタンプして可観測性を確保する。
 */

import type { MiddlewareHandler } from 'hono';
import { createPinoLogger, type AppLogger } from '../../../infrastructure/logging/pino-logger';

export type LoggerVars = {
  Variables: {
    logger: AppLogger;
    requestId: string;
  };
};

/** 32 文字 hex の id を生成 */
function newRequestId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

let baseLoggerInstance: AppLogger | null = null;
function getBaseLogger(level?: string): AppLogger {
  if (baseLoggerInstance) return baseLoggerInstance;
  baseLoggerInstance = createPinoLogger(level ?? 'info');
  return baseLoggerInstance;
}

/**
 * リクエストロガー middleware
 *
 * @returns Hono middleware handler
 */
export function requestLogger(): MiddlewareHandler<LoggerVars & { Bindings: { LOG_LEVEL?: string } }> {
  return async (c, next) => {
    const requestId = c.req.header('x-request-id') ?? newRequestId();
    const base = getBaseLogger(c.env.LOG_LEVEL);
    const child = base.child({ requestId });
    c.set('logger', child);
    c.set('requestId', requestId);
    c.header('x-request-id', requestId);

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
