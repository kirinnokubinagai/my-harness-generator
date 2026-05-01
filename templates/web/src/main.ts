/**
 * 概要: アプリケーションのエントリポイント。
 *       Clean Architecture の outermost にあたり、
 *       依存性注入（DI）と Hono サーバの起動だけを行う。
 */
import { serve } from '@hono/node-server';
import { createApp } from './interfaces/http/app';
import { loadConfig } from './infrastructure/config/load-config';
import { createPostgresUserRepository } from './infrastructure/persistence/postgres-user-repository';
import { createResendEmailSender } from './infrastructure/email/resend-email-sender';
import { createPinoLogger } from './infrastructure/logging/pino-logger';

/**
 * アプリケーションを起動する。
 *
 * @returns 起動した Hono アプリケーションのサーバインスタンス
 */
async function bootstrap(): Promise<void> {
  const applicationConfig = loadConfig();
  const structuredLogger = createPinoLogger(applicationConfig.logLevel);

  const userRepository = createPostgresUserRepository(applicationConfig.databaseUrl);
  const emailSender = createResendEmailSender(applicationConfig.resendApiKey, applicationConfig.emailFromAddress);

  const honoApplication = createApp({ userRepository, emailSender, logger: structuredLogger });

  serve({ fetch: honoApplication.fetch, port: applicationConfig.port }, (info) => {
    structuredLogger.info({ port: info.port }, 'サーバを起動しました');
  });
}

bootstrap().catch((unexpectedError) => {
  // 起動失敗は復旧不能なのでプロセスを終了する
  // biome-ignore lint/suspicious/noConsole: bootstrap 失敗時はロガー初期化前のため例外的に許可
  console.error('起動に失敗しました', unexpectedError);
  process.exit(1);
});
