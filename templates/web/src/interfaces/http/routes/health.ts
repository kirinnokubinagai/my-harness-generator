/**
 * 概要: ヘルスチェック用のルーター。
 *       - GET /healthz: プロセス生存確認（DB 不要、即 200）。
 *       - GET /livez : /healthz のエイリアス（k8s 互換）。
 *       - GET /readyz: 依存先含む準備完了確認。DB ping 失敗で 503。
 *       - GET /health: legacy エイリアス、旧 4.x クライアント互換のため /healthz と同等。
 *
 *       本ファイルは Clean Architecture の interfaces 層。具体的な ping 実装は
 *       infrastructure 層から DI することで Workers / Node 両対応にする。
 */

import { Hono } from 'hono';
import type { Env } from '../../../main';

/** D1 / 外部依存への ping を伴うヘルスルーター */
export const healthRoute = new Hono<{ Bindings: Env }>()
  .get('/healthz', (c) => c.json({ ok: true, ts: new Date().toISOString() }))
  .get('/livez', (c) => c.json({ ok: true, ts: new Date().toISOString() }))
  .get('/health', (c) => c.json({ ok: true, ts: new Date().toISOString() }))
  .get('/readyz', async (c) => {
    const checks: Record<string, 'ok' | 'fail'> = {};
    let allOk = true;

    try {
      await c.env.DB.prepare('SELECT 1').first();
      checks.db = 'ok';
    } catch {
      checks.db = 'fail';
      allOk = false;
    }

    return c.json(
      { ok: allOk, checks, ts: new Date().toISOString() },
      allOk ? 200 : 503,
    );
  });
