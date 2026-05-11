/**
 * ヘルスチェックエンドポイント
 *
 * - `/healthz` — プロセス生存確認 (DB 不要)
 * - `/readyz`  — 依存先含む準備完了確認 (DB ping + 外部サービス smoke)
 * - `/livez`   — `/healthz` のエイリアス (k8s 互換)
 */

import { Hono } from "hono";

export type HealthDeps = {
  /** DB ping 関数。成功で true、失敗で例外または false */
  pingDb: () => Promise<boolean>;
  /** 任意の追加 smoke check (外部 API など) */
  extraChecks?: Record<string, () => Promise<boolean>>;
};

export function healthRoutes(deps: HealthDeps) {
  const app = new Hono();

  app.get("/healthz", (c) => c.json({ ok: true, ts: new Date().toISOString() }));
  app.get("/livez", (c) => c.json({ ok: true, ts: new Date().toISOString() }));

  app.get("/readyz", async (c) => {
    const checks: Record<string, "ok" | "fail"> = {};
    let allOk = true;

    try {
      checks.db = (await deps.pingDb()) ? "ok" : "fail";
    } catch {
      checks.db = "fail";
    }
    if (checks.db === "fail") allOk = false;

    if (deps.extraChecks) {
      for (const [name, fn] of Object.entries(deps.extraChecks)) {
        try {
          checks[name] = (await fn()) ? "ok" : "fail";
        } catch {
          checks[name] = "fail";
        }
        if (checks[name] === "fail") allOk = false;
      }
    }

    return c.json(
      { ok: allOk, checks, ts: new Date().toISOString() },
      allOk ? 200 : 503,
    );
  });

  return app;
}
