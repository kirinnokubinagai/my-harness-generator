/**
 * 概要: ヘルスチェック用のルーター。
 *       依存外部リソース（DB / メール）の状態は含めず、純粋にプロセスが生きているかだけを返す。
 */

import { Hono } from 'hono';

/**
 * GET /health: アプリケーションが起動していることを確認するエンドポイント。
 */
export const healthRoute = new Hono().get('/health', (httpContext) =>
  httpContext.json({ status: 'ok', timestamp: new Date().toISOString() }),
);
