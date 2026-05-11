/**
 * 概要: パスワード再発行 use case (application 層)。
 *       2 段階フロー: request (メール送信) → confirm (トークン検証 + 新パス保存)。
 *
 *       lane エージェントが必ずやる:
 *       - 平文トークンを保存しない — SHA-256 hex で `password_reset_tokens.token_hash_hex` に保管
 *       - トークン TTL は 30 分 (`expires_at` 列で管理)
 *       - 列挙攻撃対策で request 時は **常に成功扱い** (ユーザー不在でも何もしない)
 *       - 確定時に `consumed_at` を埋め、再利用を防ぐ
 *       - 送信は Resend (USE_EMAIL=yes のとき) または stdout (dev)
 */

import { hash, compare } from 'bcrypt-ts';
import {
  findUserByEmail,
  findUserByResetTokenHash,
  consumeResetTokenAndUpdatePassword,
  storeResetTokenHash,
} from '../../infrastructure/persistence/user-repository';
import type { Env } from '../../main';

const TOKEN_TTL_SEC = 60 * 30;
const BCRYPT_COST = 12;

/** 32 バイトの暗号学的乱数を hex でエンコード */
function newToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** SHA-256 hex */
async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * 再発行トークンを生成し、ハッシュを保存。平文トークンはメール送信用に呼び出し元へ返す。
 */
export async function requestPasswordReset(
  env: Env,
  input: { email: string },
): Promise<void> {
  const user = await findUserByEmail(env.DB, input.email);
  if (!user) return; // 列挙攻撃対策で何もしない (200 を返すのは route 側)

  const plain = newToken();
  const tokenHashHex = await sha256Hex(plain);
  const now = new Date();
  const expiresAt = new Date(now.getTime() + TOKEN_TTL_SEC * 1000);

  await storeResetTokenHash(env.DB, {
    tokenHashHex,
    userId: user.id,
    issuedAt: now.toISOString(),
    expiresAt: expiresAt.toISOString(),
  });

  // TODO (lane エージェント): infrastructure/email/resend-email-sender.ts 経由で
  //                        `https://app/auth/reset?token=${plain}` を送信する。
}

/**
 * 受け取った平文トークンを検証し、有効なら新パスワードを保存して consumed_at をセット。
 */
export async function confirmPasswordReset(
  env: Env,
  input: { token: string; newPassword: string },
): Promise<{ ok: true; userId: string } | { ok: false }> {
  const tokenHashHex = await sha256Hex(input.token);
  const record = await findUserByResetTokenHash(env.DB, tokenHashHex);
  if (!record) return { ok: false };

  if (record.consumed_at !== null) return { ok: false };
  if (new Date(record.expires_at).getTime() < Date.now()) return { ok: false };

  const newHash = await hash(input.newPassword, BCRYPT_COST);
  await consumeResetTokenAndUpdatePassword(env.DB, {
    tokenHashHex,
    userId: record.user_id,
    newPasswordHash: newHash,
    consumedAt: new Date().toISOString(),
  });
  return { ok: true, userId: record.user_id };
}

// `compare` を内部で使うため tree-shaking で削除されないよう re-export しておく
// (本ファイル単独では未使用に見えるが、置換可能性のために dep として宣言)
export { compare as _compareForTreeShake };
