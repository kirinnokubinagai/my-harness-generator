/**
 * 概要: パスワードリセットメールのテンプレート（HTML + plain text）。
 *       本格運用時は @react-email/components で組むのが推奨だが、依存を抑えた素朴な実装にしている。
 */

/**
 * テンプレートに渡す入力。
 */
export interface PasswordResetTemplateInput {
  displayName: string;
  resetLinkUrl: string;
  expiresAt: Date;
}

/**
 * テンプレートの出力。
 */
export interface PasswordResetTemplateOutput {
  html: string;
  text: string;
}

/**
 * パスワードリセットメールを描画する。
 *
 * @param templateInput - 描画に必要な値
 * @returns html / text のペア
 */
export function renderPasswordResetEmail(templateInput: PasswordResetTemplateInput): PasswordResetTemplateOutput {
  const formattedExpiresAt = templateInput.expiresAt.toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo' });

  const text = [
    `${templateInput.displayName} さん`,
    '',
    'パスワード再設定のリクエストを受け付けました。',
    '以下のリンクから 30 分以内に新しいパスワードを設定してください。',
    '',
    templateInput.resetLinkUrl,
    '',
    `有効期限: ${formattedExpiresAt}`,
    '',
    'このメールに心当たりがない場合は、無視してください。',
  ].join('\n');

  const html = `<!DOCTYPE html><html lang="ja"><body style="font-family: -apple-system, 'Hiragino Kaku Gothic ProN', sans-serif; line-height: 1.7; color: #1c1917;"><p>${escapeHtml(templateInput.displayName)} さん</p><p>パスワード再設定のリクエストを受け付けました。<br>以下のリンクから 30 分以内に新しいパスワードを設定してください。</p><p><a href="${escapeHtml(templateInput.resetLinkUrl)}" style="display:inline-block;padding:12px 24px;background:#14b8a6;color:#fff;text-decoration:none;border-radius:6px;">パスワードを再設定する</a></p><p>有効期限: ${escapeHtml(formattedExpiresAt)}</p><p style="color: #78716c; font-size: 12px;">このメールに心当たりがない場合は、無視してください。</p></body></html>`;

  return { html, text };
}

/**
 * HTML 文字列としてエスケープする（XSS 対策）。
 *
 * @param unsafeText - エスケープ前の文字列
 * @returns HTML 安全な文字列
 */
function escapeHtml(unsafeText: string): string {
  return unsafeText
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}
