/**
 * 概要: Playwright の設定。
 *       環境変数 BASE_URL を起点に dev / stage / prod を切り替える。
 *       BASE_URL は GitHub Actions の `vars.DEV_URL` / `vars.STAGE_URL` / `vars.PROD_URL` から注入する。
 */

import { defineConfig, devices } from '@playwright/test';

const baseUrlFromEnvironment = process.env.BASE_URL ?? 'http://localhost:3000';
const isContinuousIntegration = process.env.CI === 'true';

export default defineConfig({
  testDir: './tests/e2e/web',
  fullyParallel: true,
  forbidOnly: isContinuousIntegration,
  retries: isContinuousIntegration ? 2 : 0,
  workers: isContinuousIntegration ? 2 : undefined,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: baseUrlFromEnvironment,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    locale: 'ja-JP',
    timezoneId: 'Asia/Tokyo',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    { name: 'mobile-chrome', use: { ...devices['Pixel 8'] } },
    { name: 'mobile-safari', use: { ...devices['iPhone 15'] } },
  ],
});
