/**
 * 概要: audit-log のテスト。recordAudit がアダプタへ正しいレコードを渡すことを検証する。
 */

import { describe, it, expect, vi } from 'vitest';
import { recordAudit, drizzleAuditWriter } from './audit-log';

describe('recordAudit', () => {
  it('アダプタへ id / occurredAt 付きで書き込むこと', async () => {
    const writer = vi.fn().mockResolvedValue(undefined);
    await recordAudit(writer, {
      actorId: 'user-1',
      resource: 'post:abc',
      action: 'auth.login',
      ip: '203.0.113.1',
    });
    expect(writer).toHaveBeenCalledOnce();
    const row = writer.mock.calls[0][0] as Record<string, unknown>;
    expect(row.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(row.actorId).toBe('user-1');
    expect(row.action).toBe('auth.login');
    expect(row.resource).toBe('post:abc');
    expect(row.ip).toBe('203.0.113.1');
    expect(row.metadata).toBeNull();
    expect(typeof row.occurredAt).toBe('string');
  });

  it('metadata は JSON 化されること', async () => {
    const writer = vi.fn().mockResolvedValue(undefined);
    await recordAudit(writer, {
      actorId: 'user-1',
      resource: 'order:42',
      action: 'billing.charge',
      metadata: { amount: 1000, currency: 'JPY' },
    });
    const row = writer.mock.calls[0][0] as { metadata: string };
    expect(JSON.parse(row.metadata)).toEqual({ amount: 1000, currency: 'JPY' });
  });
});

describe('drizzleAuditWriter', () => {
  it('sql テンプレートタグで INSERT を発行すること', async () => {
    const run = vi.fn().mockResolvedValue(undefined);
    const sqlTag = vi.fn((strings: TemplateStringsArray) => ({ sql: strings.join('?') }));
    const writer = drizzleAuditWriter({ run }, sqlTag);
    await writer({
      id: '00000000-0000-0000-0000-000000000001',
      actorId: 'user-1',
      action: 'auth.login',
      resource: 'user:1',
      metadata: null,
      ip: null,
      occurredAt: '2026-05-11T00:00:00Z',
    });
    expect(sqlTag).toHaveBeenCalledOnce();
    expect(run).toHaveBeenCalledOnce();
  });
});
