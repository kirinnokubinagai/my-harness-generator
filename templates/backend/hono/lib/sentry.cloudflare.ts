/**
 * Sentry 初期化ヘルパー — Cloudflare Workers 用 (`@sentry/cloudflare`)
 *
 * source-map は CI のデプロイステップでアップロード (`docs/runbooks/deploy.md`)。
 *
 * 使い方:
 *   import { withSentry } from "./lib/sentry.cloudflare";
 *   export default withSentry(app, env);
 *
 * Node / Bun デプロイの場合は `sentry.node.ts` を使うこと。
 */

import * as Sentry from "@sentry/cloudflare";
import type { Hono } from "hono";

type SentryEnv = {
  SENTRY_DSN?: string;
  ENVIRONMENT?: string;
  RELEASE?: string;
};

export function withSentry<TEnv extends SentryEnv>(
  app: Hono<{ Bindings: TEnv }>,
  env: TEnv,
) {
  if (!env.SENTRY_DSN) return app;
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

export function captureMessage(message: string, tags?: Record<string, string>) {
  Sentry.withScope((scope) => {
    if (tags) for (const [k, v] of Object.entries(tags)) scope.setTag(k, v);
    Sentry.captureMessage(message);
  });
}

export { Sentry };
