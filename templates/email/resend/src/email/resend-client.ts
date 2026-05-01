/**
 * 概要: Resend を用いたメール送信クライアント。
 *       Resend ダッシュボードでドメインを認証し、SPF / DKIM / DMARC を有効化したうえで使用すること。
 *       API キー / 送信元アドレスは必ず環境変数から注入し、ハードコード禁止。
 */

import { Resend } from 'resend';

/**
 * 送信メールの構造体。HTML と plain text の両方を含めることを推奨する（迷惑メール判定回避のため）。
 */
export interface OutgoingEmail {
  to: string;
  subject: string;
  htmlBody: string;
  textBody: string;
}

/**
 * メール送信のポート（DI 用）。
 */
export interface EmailSender {
  send(outgoingEmail: OutgoingEmail): Promise<void>;
}

/**
 * Resend を用いた EmailSender を生成する。
 *
 * @param resendApiKey - Resend の API キー（漏洩防止のため絶対にハードコード禁止）
 * @param fromAddress - 送信元メールアドレス（認証済みドメイン配下）
 * @returns EmailSender 実装
 */
export function createResendEmailSender(resendApiKey: string, fromAddress: string): EmailSender {
  const resendClient = new Resend(resendApiKey);

  return {
    async send(outgoingEmail) {
      const sendResult = await resendClient.emails.send({
        from: fromAddress,
        to: outgoingEmail.to,
        subject: outgoingEmail.subject,
        html: outgoingEmail.htmlBody,
        text: outgoingEmail.textBody,
      });

      if (sendResult.error !== null && sendResult.error !== undefined) {
        throw new Error(`メール送信に失敗しました: ${sendResult.error.message}`);
      }
    },
  };
}
