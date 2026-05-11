/**
 * フィーチャーフラグ — env-var 駆動の最小実装
 *
 * `FEATURE_FLAGS=newCheckout=true,xpEvents=10%` の形式で env から読む。
 * 値は `true` / `false` / `<percent>%` のいずれか。
 *
 * GrowthBook / LaunchDarkly に移行する場合はこのファイルを差し替えるだけで済むよう、
 * インターフェースは `isEnabled(flag, ctx)` に閉じる。
 */

export type FlagContext = {
  /** ユーザー ID — % rollout の安定 hash key に使う */
  userId?: string;
};

type FlagSpec = { kind: "bool"; value: boolean } | { kind: "percent"; value: number };

function parse(env: { FEATURE_FLAGS?: string }): Record<string, FlagSpec> {
  const out: Record<string, FlagSpec> = {};
  for (const pair of (env.FEATURE_FLAGS ?? "").split(",")) {
    const [k, v] = pair.split("=").map((s) => s?.trim());
    if (!k || !v) continue;
    if (v === "true" || v === "false") {
      out[k] = { kind: "bool", value: v === "true" };
    } else if (/^\d+%$/.test(v)) {
      out[k] = { kind: "percent", value: Number.parseInt(v, 10) };
    }
  }
  return out;
}

/** 0..99 の安定 hash (FNV-1a) */
function bucketOf(input: string): number {
  let h = 2166136261;
  for (let i = 0; i < input.length; i += 1) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h) % 100;
}

/**
 * フラグが有効か判定する
 *
 * @param env - FEATURE_FLAGS を含む環境変数
 * @param flag - フラグ名
 * @param ctx - 判定文脈 (userId など)
 */
export function isEnabled(
  env: { FEATURE_FLAGS?: string },
  flag: string,
  ctx: FlagContext = {},
): boolean {
  const spec = parse(env)[flag];
  if (!spec) return false;
  if (spec.kind === "bool") return spec.value;
  const seed = ctx.userId ?? "anonymous";
  return bucketOf(`${flag}:${seed}`) < spec.value;
}
