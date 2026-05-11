/**
 * 概要: 認証エンドポイント (OpenAPI 対応)。
 *       本ファイルは interfaces 層 — 実際の認証ロジックは application 層に委譲する。
 *       lane エージェントは `application/auth/{login,password-reset}.ts` を実装する。
 *
 *       Production-grade に必要な要素を全部使う参照実装:
 *       - rate-limit (ルート個別)
 *       - audit-log (失敗 / 成功どちらも)
 *       - Zod スキーマで入力検証 (422 on rejection)
 *       - OpenAPI で API doc 自動生成
 */

import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { sql } from 'drizzle-orm';
import { rateLimit } from '../middleware/rate-limit';
import { recordAudit, drizzleAuditWriter, type AuditAction } from '../../../infrastructure/audit/audit-log';
import { createDrizzleClient } from '../../../db/client';
import { authenticate } from '../../../application/auth/login';
import { requestPasswordReset, confirmPasswordReset } from '../../../application/auth/password-reset';
import type { Env } from '../../../main';

const LoginRequest = z.object({
  email: z.string().email('メールアドレスの形式が正しくありません').max(255),
  password: z.string().min(8, 'パスワードは 8 文字以上で入力してください').max(128),
});

const LoginResponse = z.object({
  success: z.literal(true),
  data: z.object({
    accessToken: z.string(),
    expiresIn: z.number().int().positive(),
  }),
});

const ErrorResponse = z.object({
  success: z.literal(false),
  error: z.object({
    code: z.string(),
    message: z.string(),
    details: z.unknown().optional(),
  }),
});

const PasswordResetRequest = z.object({
  email: z.string().email().max(255),
});

const PasswordResetConfirm = z.object({
  token: z.string().min(32).max(256),
  newPassword: z.string().min(8).max(128),
});

const SuccessAck = z.object({ success: z.literal(true) });

const loginRoute = createRoute({
  method: 'post',
  path: '/login',
  tags: ['auth'],
  summary: 'ログイン',
  request: { body: { content: { 'application/json': { schema: LoginRequest } } } },
  responses: {
    200: { description: 'ログイン成功', content: { 'application/json': { schema: LoginResponse } } },
    401: { description: '認証失敗', content: { 'application/json': { schema: ErrorResponse } } },
    422: { description: 'バリデーションエラー', content: { 'application/json': { schema: ErrorResponse } } },
    429: { description: 'レート制限', content: { 'application/json': { schema: ErrorResponse } } },
  },
});

const passwordResetRequestRoute = createRoute({
  method: 'post',
  path: '/password-reset/request',
  tags: ['auth'],
  summary: 'パスワード再発行リクエスト',
  request: { body: { content: { 'application/json': { schema: PasswordResetRequest } } } },
  responses: {
    200: { description: '常に成功を返す (列挙攻撃対策)', content: { 'application/json': { schema: SuccessAck } } },
    429: { description: 'レート制限', content: { 'application/json': { schema: ErrorResponse } } },
  },
});

const passwordResetConfirmRoute = createRoute({
  method: 'post',
  path: '/password-reset/confirm',
  tags: ['auth'],
  summary: 'パスワード再発行確定',
  request: { body: { content: { 'application/json': { schema: PasswordResetConfirm } } } },
  responses: {
    200: { description: '再設定成功', content: { 'application/json': { schema: SuccessAck } } },
    400: { description: 'トークン無効 / 期限切れ', content: { 'application/json': { schema: ErrorResponse } } },
    422: { description: 'バリデーションエラー', content: { 'application/json': { schema: ErrorResponse } } },
  },
});

function clientIp(headerValue: string | undefined, forwardedFor: string | undefined): string | undefined {
  return headerValue ?? forwardedFor?.split(',')[0]?.trim();
}

async function audit(env: Env, action: AuditAction, resource: string, ip?: string, metadata?: Record<string, unknown>) {
  const db = createDrizzleClient(env.DB);
  const writer = drizzleAuditWriter(db, sql);
  await recordAudit(writer, { actorId: 'anonymous', resource, action, ip, metadata });
}

export const authRoute = new OpenAPIHono<{ Bindings: Env }>()
  .use('/login', rateLimit({ bucket: 'login', limit: 5, windowSec: 900 }))
  .use('/password-reset/request', rateLimit({ bucket: 'password-reset', limit: 3, windowSec: 3600 }))
  .openapi(loginRoute, async (c) => {
    const { email, password } = c.req.valid('json');
    const ip = clientIp(c.req.header('CF-Connecting-IP'), c.req.header('X-Forwarded-For'));
    const result = await authenticate(c.env, { email, password });

    if (!result.ok) {
      await audit(c.env, 'auth.login', `email:${email}`, ip, { outcome: 'failure', reason: result.reason });
      return c.json(
        { success: false as const, error: { code: 'AUTH_INVALID', message: 'メールアドレスまたはパスワードが正しくありません' } },
        401,
      );
    }

    await audit(c.env, 'auth.login', `user:${result.userId}`, ip, { outcome: 'success' });
    return c.json(
      { success: true as const, data: { accessToken: result.accessToken, expiresIn: result.expiresIn } },
      200,
    );
  })
  .openapi(passwordResetRequestRoute, async (c) => {
    const { email } = c.req.valid('json');
    const ip = clientIp(c.req.header('CF-Connecting-IP'), c.req.header('X-Forwarded-For'));
    await requestPasswordReset(c.env, { email });
    // 列挙攻撃を防ぐため、ユーザーの存在に関わらず常に 200 を返す。
    await audit(c.env, 'auth.password_change', `email:${email}`, ip, { phase: 'request' });
    return c.json({ success: true as const }, 200);
  })
  .openapi(passwordResetConfirmRoute, async (c) => {
    const { token, newPassword } = c.req.valid('json');
    const ip = clientIp(c.req.header('CF-Connecting-IP'), c.req.header('X-Forwarded-For'));
    const result = await confirmPasswordReset(c.env, { token, newPassword });
    if (!result.ok) {
      return c.json(
        { success: false as const, error: { code: 'TOKEN_INVALID', message: 'トークンが無効または期限切れです' } },
        400,
      );
    }
    await audit(c.env, 'auth.password_change', `user:${result.userId}`, ip, { phase: 'confirm' });
    return c.json({ success: true as const }, 200);
  });
