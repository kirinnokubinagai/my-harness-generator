/**
 * 概要: Cloudflare Workers のリクエストごとに D1 バインディングから Drizzle クライアントを取得する。
 *       Workers の `env.DB`（D1Database）を引数に取り、Drizzle インスタンスを返す。
 */

import { drizzle } from 'drizzle-orm/d1';
import type { D1Database } from '@cloudflare/workers-types';
import * as schema from './schema';

/**
 * D1 バインディングから Drizzle クライアントを生成する。
 *
 * @param d1Binding - Cloudflare Workers の env.DB バインディング
 * @returns Drizzle クライアント（schema 付き）
 */
export function createDrizzleClient(d1Binding: D1Database) {
  return drizzle(d1Binding, { schema, casing: 'snake_case' });
}

export type DrizzleClient = ReturnType<typeof createDrizzleClient>;
