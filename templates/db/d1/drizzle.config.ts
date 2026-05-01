/**
 * 概要: Drizzle Kit の設定（Cloudflare D1 用、SQLite ダイアレクト）。
 *       マイグレーションは `pnpm db:generate` → `pnpm db:migrate:local` → `pnpm db:migrate:remote` で適用する。
 *       `drizzle-kit push` は使用禁止（マイグレーション履歴・ロールバックが残らないため）。
 */

import { defineConfig } from 'drizzle-kit';

const isRemoteApply = process.env.DRIZZLE_REMOTE === 'true';

export default defineConfig({
  schema: './src/db/schema.ts',
  out: './drizzle',
  dialect: 'sqlite',
  ...(isRemoteApply
    ? {
        driver: 'd1-http',
        dbCredentials: {
          accountId: requireEnv('CLOUDFLARE_ACCOUNT_ID'),
          databaseId: requireEnv('CLOUDFLARE_D1_DATABASE_ID'),
          token: requireEnv('CLOUDFLARE_API_TOKEN'),
        },
      }
    : {}),
  strict: true,
  verbose: true,
});

/**
 * 必須環境変数を取得する。未設定なら起動時例外を投げる。
 *
 * @param environmentVariableName - 取得対象の環境変数名
 * @returns 環境変数の値
 * @throws Error 環境変数が未設定の場合
 */
function requireEnv(environmentVariableName: string): string {
  const value = process.env[environmentVariableName];
  if (value === undefined || value === '') {
    throw new Error(`${environmentVariableName} が未設定です。.env または SOPS から注入してください。`);
  }
  return value;
}
