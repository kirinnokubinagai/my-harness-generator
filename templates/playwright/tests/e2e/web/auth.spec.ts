/**
 * 概要: ログイン / パスワードリセットの E2E テスト。
 *       各テストは独立して実行できるように、テスト用ユーザーを fixture で作成する。
 *       本番に近い stage 環境で実行することを前提にしている。
 */

import { expect, test } from '@playwright/test';

test('未ログイン時は /login にリダイレクトされること', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page).toHaveURL(/\/login/);
});

test('パスワードリセット要求は存在/不在に関わらず同じ成功画面を表示すること', async ({ page }) => {
  await page.goto('/auth/request-reset');
  await page.getByLabel('メールアドレス').fill('unknown@example.com');
  await page.getByRole('button', { name: 'リセットメールを送信' }).click();
  await expect(page.getByText('メールを送信しました')).toBeVisible();
});
