/**
 * Sentry (Cloudflare Workers) 初期化ヘルパー
 *
 * `@sentry/cloudflare` を使って未捕捉例外と意図的 capture を Sentry に送る。
 * source-map は CI のデプロイステップでアップロード (`docs/runbooks/deploy.md`)。
 *
 * 使い方:
 *   import { withSentry } from "./lib/sentry";
 *   export default withSentry(app, env);
 */

import * as Sentry from "@sentry/cloudflare";
import type { Hono } from "hono";

type SentryEnv = {
  SENTRY_DSN?: string;
  ENVIRONMENT?: string;
  RELEASE?: string;
};

/**
 * Hono app を Sentry でラップする
 *
 * @param app - Hono インスタンス
 * @param env - SENTRY_DSN / ENVIRONMENT / RELEASE
 */
export function withSentry<TEnv extends SentryEnv>(
  app: Hono<{ Bindings: TEnv }>,
  env: TEnv,
) {
  if (!env.SENTRY_DSN) {
    return app;
  }

  return Sentry.withSentry(
    () => ({
      dsn: env.SENTRY_DSN,
      environment: env.ENVIRONMENT ?? "production",
      release: env.RELEASE,
      tracesSampleRate: 0.1,
      sendDefaultPii: false,
    }),
    app.fetch as unknown as ExportedHandlerFetchHandler<TEnv>,
  );
}

/** 任意イベント送信 (handler 内から使う) */
export function captureMessage(message: string, tags?: Record<string, string>) {
  Sentry.withScope((scope) => {
    if (tags) for (const [k, v] of Object.entries(tags)) scope.setTag(k, v);
    Sentry.captureMessage(message);
  });
}

export { Sentry };
