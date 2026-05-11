/**
 * 概要: idempotency middleware のテスト。
 *       同一 `Idempotency-Key` での再送がキャッシュ応答を返すこと、
 *       不正キー長で 400 になることを検証する。
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { Hono } from 'hono';
import { idempotency } from './idempotency';

class MemoryKV {
  private store = new Map<string, string>();
  async get(key: string): Promise<string | null> {
    return this.store.get(key) ?? null;
  }
  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
}

describe('idempotency', () => {
  let kv: MemoryKV;
  let app: Hono<{ Bindings: { IDEMPOTENCY_KV: MemoryKV } }>;
  let counter: number;

  beforeEach(() => {
    kv = new MemoryKV();
    counter = 0;
    app = new Hono();
    app.use('*', idempotency());
    app.post('/items', (c) => {
      counter += 1;
      return c.json({ ok: true, n: counter });
    });
  });

  it('GET には適用されないこと', async () => {
    const env = { IDEMPOTENCY_KV: kv };
    app.get('/x', (c) => c.json({ ok: true }));
    const res = await app.request('/x', { method: 'GET' }, env);
    expect(res.status).toBe(200);
  });

  it('Idempotency-Key 無しなら通常通過すること', async () => {
    const env = { IDEMPOTENCY_KV: kv };
    const res1 = await app.request('/items', { method: 'POST' }, env);
    const res2 = await app.request('/items', { method: 'POST' }, env);
    const b1 = (await res1.json()) as { n: number };
    const b2 = (await res2.json()) as { n: number };
    expect(b2.n).toBe(b1.n + 1);
  });

  it('同一キー再送でキャッシュ応答が返ること', async () => {
    const env = { IDEMPOTENCY_KV: kv };
    const headers = { 'Idempotency-Key': 'abcd1234' };
    const res1 = await app.request('/items', { method: 'POST', headers }, env);
    const res2 = await app.request('/items', { method: 'POST', headers }, env);
    expect(res2.headers.get('Idempotent-Replay')).toBe('true');
    expect(await res2.json()).toEqual(await res1.clone().json());
  });

  it('キー長が短すぎる場合 400 を返すこと', async () => {
    const env = { IDEMPOTENCY_KV: kv };
    const res = await app.request('/items', {
      method: 'POST',
      headers: { 'Idempotency-Key': 'short' },
    }, env);
    expect(res.status).toBe(400);
  });
});
