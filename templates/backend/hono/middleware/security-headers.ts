/**
 * セキュリティヘッダー middleware (Hono)
 *
 * すべての HTTP レスポンスに `rules/production.md` で定義した OWASP 推奨ヘッダーを付与する。
 * CSP は `default-src 'self'` から始め、必要なオリジンのみ追加すること。
 */

import type { MiddlewareHandler } from "hono";

/** デフォルト CSP — 必要に応じて拡張する */
const DEFAULT_CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: https:",
  "font-src 'self' data:",
  "connect-src 'self'",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
].join("; ");

/**
 * セキュリティヘッダー middleware を生成する
 *
 * @param options.csp - CSP 文字列 (省略時はデフォルト)
 * @param options.hstsMaxAge - HSTS の max-age 秒 (省略時は 1 年)
 */
export function securityHeaders(options: {
  csp?: string;
  hstsMaxAge?: number;
} = {}): MiddlewareHandler {
  const csp = options.csp ?? DEFAULT_CSP;
  const hstsMaxAge = options.hstsMaxAge ?? 31_536_000;

  return async (c, next) => {
    await next();
    c.header("Content-Security-Policy", csp);
    c.header(
      "Strict-Transport-Security",
      `max-age=${hstsMaxAge}; includeSubDomains; preload`,
    );
    c.header("X-Frame-Options", "DENY");
    c.header("X-Content-Type-Options", "nosniff");
    c.header("Referrer-Policy", "strict-origin-when-cross-origin");
    c.header(
      "Permissions-Policy",
      "geolocation=(), microphone=(), camera=(), payment=(), usb=()",
    );
    c.header("Cross-Origin-Opener-Policy", "same-origin");
    c.header("Cross-Origin-Resource-Policy", "same-site");
    c.header("X-DNS-Prefetch-Control", "off");
  };
}
