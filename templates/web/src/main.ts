/**
 * 概要: Cloudflare Workers のエントリポイント。
 *       Clean Architecture の outermost にあたり、依存性注入（DI）と
 *       Hono アプリの起動だけを行う。
 *
 *       本番デプロイは Workers (Alchemy + wrangler)。ローカル開発は `wrangler dev`
 *       を推奨。`@hono/node-server` 経由の Node 起動は本テンプレートでは未サポート。
 */

import type { D1Database, KVNamespace, R2Bucket, ExecutionContext } from '@cloudflare/workers-types';
import { createApp } from './interfaces/http/app';

/** Workers バインディング + シークレット型 */
export type Env = {
  DB: D1Database;
  RATE_LIMIT_KV: KVNamespace;
  IDEMPOTENCY_KV: KVNamespace;
  BackupBucket: R2Bucket;
  ALLOWED_ORIGINS: string;
  SENTRY_DSN?: string;
  ENVIRONMENT?: string;
  RELEASE?: string;
  LOG_LEVEL?: string;
  FEATURE_FLAGS?: string;
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const app = createApp(env);
    return app.fetch(request, env, ctx);
  },
};
