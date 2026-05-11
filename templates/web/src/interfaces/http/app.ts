/**
 * 概要: Hono アプリケーションを構築する。
 *       interfaces 層に位置し、HTTP プロトコルと application 層の橋渡しに専念する。
 *       ビジネスロジックは application 層に書くこと。
 *
 *       Production middleware を `rules/production.md` の順序で適用する:
 *       request-logger → secure-headers → cors → idempotency → routes
 *       rate-limit はルート個別に適用する（全 API に掛けたい場合は createApp で追加）。
 */

import { Hono } from 'hono';
import { secureHeaders } from 'hono/secure-headers';
import { requestLogger } from './middleware/request-logger';
import { strictCors } from './middleware/cors';
import { idempotency } from './middleware/idempotency';
import { healthRoute } from './routes/health';
import type { Env } from '../../main';

/**
 * Hono アプリケーションを構築する。
 *
 * @param env - Workers バインディング + シークレット
 * @returns 構築済み Hono インスタンス
 */
export function createApp(env: Env): Hono<{ Bindings: Env }> {
  const app = new Hono<{ Bindings: Env }>();

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

  return app;
}
