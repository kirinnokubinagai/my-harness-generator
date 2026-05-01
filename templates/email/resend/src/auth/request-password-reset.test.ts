/**
 * 概要: パスワードリセット要求ユースケースの単体テスト（TDD）。
 *       存在/不在で同じレスポンス、SHA-256 でハッシュ保管、30 分 TTL を保証する。
 */

import { describe, expect, it, vi } from 'vitest';
import { requestPasswordReset } from './request-password-reset';
import type { EmailSender } from '../email/resend-client';
import type { UserSummary } from './request-password-reset';

const fixtureUser: UserSummary = {
  id: '01HXYZABCDEFGHJKMNPQRSTVWX',
  email: 'test@example.com',
  displayName: 'テストユーザー',
};

const buildDependencies = (overrides: { findResult: UserSummary | null }) => {
  const emailSender: EmailSender = { send: vi.fn().mockResolvedValue(undefined) };
  return {
    findUserByEmail: vi.fn().mockResolvedValue(overrides.findResult),
    saveResetToken: vi.fn().mockResolvedValue(undefined),
    emailSender,
    applicationOriginUrl: 'https://app.example.com',
    generateRandomBytes: (n: number) => new Uint8Array(n).fill(7),
    sha256Hex: async (_b: Uint8Array) => 'a'.repeat(64),
    getCurrentTime: () => new Date('2026-05-01T12:00:00Z'),
  };
};

describe('requestPasswordReset', () => {
  it('該当ユーザーが存在する場合、トークンを保存してメールを送信できること', async () => {
    const dependencies = buildDependencies({ findResult: fixtureUser });
    const result = await requestPasswordReset('test@example.com', dependencies);
    expect(result).toEqual({ accepted: true });
    expect(dependencies.saveResetToken).toHaveBeenCalledTimes(1);
    expect(dependencies.emailSender.send).toHaveBeenCalledTimes(1);
  });

  it('該当ユーザーが存在しない場合でも、存在判定が漏洩しないこと', async () => {
    const dependencies = buildDependencies({ findResult: null });
    const result = await requestPasswordReset('unknown@example.com', dependencies);
    expect(result).toEqual({ accepted: true });
    expect(dependencies.saveResetToken).not.toHaveBeenCalled();
    expect(dependencies.emailSender.send).not.toHaveBeenCalled();
  });

  it('保存するトークンは SHA-256 ハッシュであること', async () => {
    const dependencies = buildDependencies({ findResult: fixtureUser });
    await requestPasswordReset('test@example.com', dependencies);
    const saved = vi.mocked(dependencies.saveResetToken).mock.calls[0]?.[0];
    expect(saved?.tokenHashHex).toMatch(/^[0-9a-f]{64}$/);
  });

  it('トークンの有効期限は発行から 30 分後であること', async () => {
    const dependencies = buildDependencies({ findResult: fixtureUser });
    await requestPasswordReset('test@example.com', dependencies);
    const saved = vi.mocked(dependencies.saveResetToken).mock.calls[0]?.[0];
    const elapsedMinutes = ((saved?.expiresAt.getTime() ?? 0) - (saved?.issuedAt.getTime() ?? 0)) / 60000;
    expect(elapsedMinutes).toBe(30);
  });
});
