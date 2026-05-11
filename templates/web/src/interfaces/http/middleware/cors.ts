/**
 * 概要: 厳格な CORS middleware — `ALLOWED_ORIGINS` 環境変数の明示許可リスト方式。
 *       `*` は本番禁止 (`rules/production.md`)。
 */

import { cors as honoCors } from 'hono/cors';
import type { MiddlewareHandler } from 'hono';

/**
 * 許可リストを env から取得して CORS middleware を生成する。
 *
 * @param env - `ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com`
 */
export function strictCors(env: { ALLOWED_ORIGINS?: string }): MiddlewareHandler {
  const isProduction = (env as { ENVIRONMENT?: string }).ENVIRONMENT === 'prod';
  const configured = (env.ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const allowed = configured.length > 0
    ? configured
    : isProduction
      ? []
      : ['http://localhost:3000', 'http://localhost:8787', 'http://127.0.0.1:3000'];

  if (allowed.length === 0) {
    throw new Error(
      'ALLOWED_ORIGINS が未設定です。本番 (ENVIRONMENT=prod) では明示的に許可するオリジンを指定してください。',
    );
  }

  return honoCors({
    origin: (origin) => (allowed.includes(origin) ? origin : null),
    credentials: true,
    allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key', 'x-request-id'],
    exposeHeaders: ['x-request-id', 'Idempotent-Replay'],
    maxAge: 600,
  });
}
