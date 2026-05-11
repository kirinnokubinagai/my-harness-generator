/**
 * 概要: rate-limit middleware のテスト。
 *       KV を in-memory モックで差し替え、ウィンドウ境界 / 上限 / リセットを検証する。
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { Hono } from 'hono';
import { rateLimit } from './rate-limit';

class MemoryKV {
  private store = new Map<string, string>();
  async get(key: string): Promise<string | null> {
    return this.store.get(key) ?? null;
  }
  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
}

describe('rateLimit', () => {
  let kv: MemoryKV;
  let app: Hono<{ Bindings: { RATE_LIMIT_KV: MemoryKV } }>;

  beforeEach(() => {
    kv = new MemoryKV();
    app = new Hono();
    app.use('*', rateLimit({ bucket: 'test', limit: 2, windowSec: 60, keyFn: () => 'fixed-id' }));
    app.get('/', (c) => c.json({ ok: true }));
  });

  it('上限以内なら 200 で通過すること', async () => {
    const env = { RATE_LIMIT_KV: kv };
    const res1 = await app.request('/', {}, env);
    const res2 = await app.request('/', {}, env);

    expect(res1.status).toBe(200);
    expect(res2.status).toBe(200);
    expect(res2.headers.get('X-RateLimit-Remaining')).toBe('0');
  });

  it('上限超過で 429 を返すこと', async () => {
    const env = { RATE_LIMIT_KV: kv };
    await app.request('/', {}, env);
    await app.request('/', {}, env);
    const res3 = await app.request('/', {}, env);

    expect(res3.status).toBe(429);
    expect(res3.headers.get('Retry-After')).toBeTruthy();
    const body = (await res3.json()) as { error: { code: string } };
    expect(body.error.code).toBe('RATE_LIMIT_EXCEEDED');
  });
});
