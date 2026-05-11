/**
 * 概要: Hono (OpenAPI 対応) アプリケーションを構築する。
 *       interfaces 層に位置し、HTTP プロトコルと application 層の橋渡しに専念する。
 *       ビジネスロジックは application 層に書くこと。
 *
 *       Production middleware を `rules/production.md` の順序で適用する:
 *       request-logger → secure-headers → cors → idempotency → routes
 *       rate-limit はルート個別に適用する (`routes/auth.ts` 参照)。
 *
 *       `/openapi.json` で OpenAPI 3.1 仕様を配信、`/docs` で Scalar UI を表示する。
 */

import { OpenAPIHono } from '@hono/zod-openapi';
import { apiReference } from '@scalar/hono-api-reference';
import { secureHeaders } from 'hono/secure-headers';
import { requestLogger } from './middleware/request-logger';
import { strictCors } from './middleware/cors';
import { idempotency } from './middleware/idempotency';
import { healthRoute } from './routes/health';
import { authRoute } from './routes/auth';
import type { Env } from '../../main';

/**
 * Hono アプリケーションを構築する。
 *
 * @param env - Workers バインディング + シークレット
 * @returns 構築済み OpenAPIHono インスタンス
 */
export function createApp(env: Env): OpenAPIHono<{ Bindings: Env }> {
  const app = new OpenAPIHono<{ Bindings: Env }>();

  app.use('*', requestLogger());

  app.use(
    '*',
    secureHeaders({
      strictTransportSecurity: 'max-age=31536000; includeSubDomains; preload',
      crossOriginOpenerPolicy: 'same-origin',
      crossOriginResourcePolicy: 'same-site',
      crossOriginEmbedderPolicy: 'require-corp',
      xFrameOptions: 'DENY',
      xContentTypeOptions: 'nosniff',
      referrerPolicy: 'strict-origin-when-cross-origin',
      permissionsPolicy: { camera: [], microphone: [], geolocation: [], payment: [] },
      contentSecurityPolicy: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", 'data:', 'https:'],
        connectSrc: ["'self'"],
        frameAncestors: ["'none'"],
        baseUri: ["'self'"],
        formAction: ["'self'"],
      },
    }),
  );

  app.use('*', strictCors(env));
  app.use('*', idempotency());

  app.route('/', healthRoute);
  app.route('/auth', authRoute);

  // OpenAPI spec + Scalar UI
  app.doc('/openapi.json', {
    openapi: '3.1.0',
    info: { title: 'API', version: env.RELEASE ?? '0.0.0' },
    servers: [{ url: '/' }],
  });
  app.get('/docs', apiReference({ spec: { url: '/openapi.json' } }));

  return app;
}
