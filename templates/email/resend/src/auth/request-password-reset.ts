/**
 * 概要: パスワードリセット要求ユースケース（D1 + Resend 用）。
 *       存在/不在を応答に含めず、常に accepted: true を返すことで情報漏洩を防ぐ。
 *       依存設計: Repository 系は D1 / Drizzle、メールは Resend だが、interface で差し替え可能。
 *
 * 設計参考: OWASP Forgot Password Cheat Sheet
 *           https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html
 */

import type { EmailSender } from '../email/resend-client';
import { renderPasswordResetEmail } from '../email/templates/password-reset';

/**
 * リセットトークンの有効期限（分）。短すぎても長すぎても使い勝手とリスクが釣り合わない。
 */
const PASSWORD_RESET_TOKEN_TTL_MINUTES = 30;

/**
 * リセットトークンのバイト長。256 ビット相当のエントロピーを確保する。
 */
const PASSWORD_RESET_TOKEN_BYTE_LENGTH = 32;

/**
 * ユーザーレコードの最小情報（メール送信に必要なフィールドだけ）。
 */
export interface UserSummary {
  id: string;
  email: string;
  displayName: string;
}

/**
 * リセットトークン保存内容。
 */
export interface PasswordResetTokenRecord {
  userId: string;
  tokenHashHex: string;
  issuedAt: Date;
  expiresAt: Date;
  consumedAt: Date | null;
}

/**
 * このユースケースの依存（DI）。
 */
export interface RequestPasswordResetDependencies {
  findUserByEmail: (email: string) => Promise<UserSummary | null>;
  saveResetToken: (record: PasswordResetTokenRecord) => Promise<void>;
  emailSender: EmailSender;
  applicationOriginUrl: string;
  /** 暗号学的に安全なランダムバイト列を生成する関数 */
  generateRandomBytes: (byteLength: number) => Uint8Array;
  /** SHA-256 ハッシュを hex 文字列で返す関数 */
  sha256Hex: (input: Uint8Array) => Promise<string>;
  /** 現在時刻を取得する関数（テスタビリティのための DI） */
  getCurrentTime: () => Date;
}

/**
 * パスワードリセット要求ユースケース。
 *
 * @param requestEmail - リセット要求のあったメールアドレス
 * @param dependencies - 依存関係
 * @returns 常に \{ accepted: true \} を返す（存在判定の漏洩を防ぐため）
 */
export async function requestPasswordReset(
  requestEmail: string,
  dependencies: RequestPasswordResetDependencies,
): Promise<{ accepted: true }> {
  const targetUser = await dependencies.findUserByEmail(requestEmail);

  if (targetUser === null) {
    return { accepted: true };
  }

  const rawTokenBytes = dependencies.generateRandomBytes(PASSWORD_RESET_TOKEN_BYTE_LENGTH);
  const rawTokenHex = bytesToHex(rawTokenBytes);
  const tokenHashHex = await dependencies.sha256Hex(rawTokenBytes);

  const issuedAt = dependencies.getCurrentTime();
  const expiresAt = new Date(issuedAt.getTime() + PASSWORD_RESET_TOKEN_TTL_MINUTES * 60 * 1000);

  await dependencies.saveResetToken({
    userId: targetUser.id,
    tokenHashHex,
    issuedAt,
    expiresAt,
    consumedAt: null,
  });

  const resetLinkUrl = `${dependencies.applicationOriginUrl}/auth/reset-password?token=${rawTokenHex}`;
  const renderedEmail = renderPasswordResetEmail({
    displayName: targetUser.displayName,
    resetLinkUrl,
    expiresAt,
  });

  await dependencies.emailSender.send({
    to: targetUser.email,
    subject: 'パスワード再設定のご案内',
    htmlBody: renderedEmail.html,
    textBody: renderedEmail.text,
  });

  return { accepted: true };
}

/**
 * バイト列を hex 文字列に変換する。
 */
function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}
