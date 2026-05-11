/**
 * 概要: ログイン use case (application 層)。
 *       interfaces 層からこの関数だけを呼ぶ。実際の永続化は infrastructure 層へ。
 *
 *       lane エージェントが必ずやる:
 *       - bcrypt.compare で `password_hash` と入力を照合
 *       - 一致したら jose で JWT を生成 (HS256 + JWT_SECRET)
 *       - リフレッシュトークンを KV / DB に保存 (本テンプレでは省略)
 *       - 失敗時の reason は user-not-found / password-mismatch / account-locked 等
 */

import { compare } from 'bcrypt-ts';
import { SignJWT } from 'jose';
import { findUserByEmail } from '../../infrastructure/persistence/user-repository';
import type { Env } from '../../main';

export type AuthInput = {
  email: string;
  password: string;
};

export type AuthResult =
  | { ok: true; userId: string; accessToken: string; expiresIn: number }
  | { ok: false; reason: 'user-not-found' | 'password-mismatch' | 'account-locked' };

const ACCESS_TOKEN_TTL_SEC = 60 * 15;

/**
 * 与えられた email + password を検証し、成功時にアクセストークンを発行する。
 *
 * @param env - Workers バインディング (DB + JWT_SECRET)
 * @param input - email + password
 */
export async function authenticate(
  env: Env & { JWT_SECRET?: string },
  input: AuthInput,
): Promise<AuthResult> {
  const user = await findUserByEmail(env.DB, input.email);
  if (!user) return { ok: false, reason: 'user-not-found' };

  const match = await compare(input.password, user.password_hash);
  if (!match) return { ok: false, reason: 'password-mismatch' };

  const secret = env.JWT_SECRET;
  if (!secret) {
    // 設定不備は 500 相当 — テストで気付ける早期失敗
    throw new Error('JWT_SECRET が未設定です');
  }

  const accessToken = await new SignJWT({ sub: user.id })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(`${ACCESS_TOKEN_TTL_SEC}s`)
    .sign(new TextEncoder().encode(secret));

  return { ok: true, userId: user.id, accessToken, expiresIn: ACCESS_TOKEN_TTL_SEC };
}
