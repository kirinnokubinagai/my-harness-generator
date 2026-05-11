/**
 * 概要: Alchemy v2 (`2.0.0-beta.x`) スタック宣言。
 *       D1 / KV (RATE_LIMIT / IDEMPOTENCY) / R2 / Worker を 1 ファイルで宣言し、
 *       `bunx alchemy deploy --stage <dev|stage|prod>` で適用する。
 *
 *       シークレットは絶対にここに書かない (`rules/no-hardcoded-secrets.md`)。
 *       Cloudflare API token / Account ID は GitHub Secrets と SOPS で管理する。
 */

import * as Alchemy from 'alchemy';
import * as Cloudflare from 'alchemy/Cloudflare';
import * as Effect from 'effect/Effect';

export default Alchemy.Stack(
  'harness',
  { providers: Cloudflare.providers(), state: Cloudflare.state() },
  Effect.gen(function* () {
    const stage = process.env.STAGE ?? 'dev';

    const db = yield* Cloudflare.D1Database('Db', {
      name: `harness-${stage}`,
    });

    const rateLimitKv = yield* Cloudflare.KVNamespace('RateLimitKv', {
      title: `harness-${stage}-rate-limit`,
    });

    const idempotencyKv = yield* Cloudflare.KVNamespace('IdempotencyKv', {
      title: `harness-${stage}-idempotency`,
    });

    const backupBucket = yield* Cloudflare.R2Bucket('BackupBucket', {
      name: `harness-${stage}-backups`,
    });

    const worker = yield* Cloudflare.Worker('Api', {
      main: './src/main.ts',
      url: true,
      compatibility_date: '2026-04-01',
      compatibility_flags: ['nodejs_compat'],
      bindings: {
        DB: db,
        RATE_LIMIT_KV: rateLimitKv,
        IDEMPOTENCY_KV: idempotencyKv,
        BackupBucket: backupBucket,
      },
      vars: {
        ENVIRONMENT: stage,
        LOG_LEVEL: stage === 'prod' ? 'warn' : 'info',
      },
    });

    return {
      worker_url: worker.url,
      d1_id: db.id,
      rate_limit_kv_id: rateLimitKv.id,
      idempotency_kv_id: idempotencyKv.id,
      bucket: backupBucket.name,
    };
  }),
);
