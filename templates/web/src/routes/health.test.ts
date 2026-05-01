/**
 * 概要: ヘルスチェックルーターの単体テスト。
 *       TDD のサンプルとして、最小限の振る舞いだけを保証する。
 */

import { describe, expect, it } from 'vitest';
import { healthRoute } from './health';

describe('healthRoute', () => {
  it('GET /health で 200 と status: ok を返すこと', async () => {
    const response = await healthRoute.request('/health');
    expect(response.status).toBe(200);
    const body = (await response.json()) as { status: string };
    expect(body.status).toBe('ok');
  });
});
