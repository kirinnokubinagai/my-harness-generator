/**
 * 概要: pino をベースにした構造化ロガーファクトリ。
 *       Workers / Node 両対応で動く最低限の API に絞っている。
 *       認可ヘッダーや Cookie、`password` プロパティは redact する。
 */

import pino, { type Logger } from 'pino';

/** harness で使うロガー型 */
export type AppLogger = Logger;

/**
 * pino ロガーを生成する。
 *
 * @param level - ログレベル（info / debug / warn / error）
 * @returns pino インスタンス
 */
export function createPinoLogger(level: string): AppLogger {
  return pino({
    level,
    base: { service: 'api' },
    timestamp: pino.stdTimeFunctions.isoTime,
    redact: {
      paths: ['req.headers.authorization', 'req.headers.cookie', '*.password', '*.token'],
      remove: true,
    },
  });
}
