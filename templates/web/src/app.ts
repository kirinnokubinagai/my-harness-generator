/**
 * 概要: Hono アプリケーションを構築する。
 *       interfaces 層に位置し、HTTP プロトコルと application 層の橋渡しに専念する。
 *       ビジネスロジックは application 層に書くこと。
 */

import { Hono } from 'hono';
import { logger as honoLogger } from 'hono/logger';
import { secureHeaders } from 'hono/secure-headers';
import { cors } from 'hono/cors';
import { healthRoute } from './routes/health';

/**
 * Hono アプリケーションを構築する。
 *
 * @returns 構築済み Hono インスタンス
 */
export function createApp(): Hono {
  const app = new Hono();
  app.use('*', honoLogger());
  app.use('*', secureHeaders());
  app.use(
    '*',
    cors({
      origin: (process.env.ALLOWED_ORIGINS ?? '').split(',').filter((origin) => origin !== ''),
      credentials: true,
    }),
  );
  app.route('/', healthRoute);
  return app;
}
