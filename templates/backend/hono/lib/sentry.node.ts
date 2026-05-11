/**
 * Sentry 初期化ヘルパー — Node / Bun 用 (`@sentry/node`)
 *
 * Cloudflare Workers にデプロイする場合は `sentry.cloudflare.ts` を使うこと。
 *
 * 起動時に `initSentry(env)` を 1 度呼び、Hono に `sentryMiddleware()` をマウントする。
 */

import * as Sentry from "@sentry/node";
import type { MiddlewareHandler } from "hono";

type SentryEnv = {
  SENTRY_DSN?: string;
  ENVIRONMENT?: string;
  RELEASE?: string;
};

/** プロセス開始直後に 1 度だけ呼ぶ */
export function initSentry(env: SentryEnv): void {
  if (!env.SENTRY_DSN) return;
  Sentry.init({
    dsn: env.SENTRY_DSN,
    environment: env.ENVIRONMENT ?? "production",
    release: env.RELEASE,
    tracesSampleRate: 0.1,
    sendDefaultPii: false,
  });
}

/** Hono にマウントしてリクエスト中の未捕捉例外を Sentry に流す */
export function sentryMiddleware(): MiddlewareHandler {
  return async (c, next) => {
    try {
      await next();
    } catch (err) {
      Sentry.captureException(err);
      throw err;
    }
  };
}

export function captureMessage(message: string, tags?: Record<string, string>) {
  Sentry.withScope((scope) => {
    if (tags) for (const [k, v] of Object.entries(tags)) scope.setTag(k, v);
    Sentry.captureMessage(message);
  });
}

export { Sentry };
