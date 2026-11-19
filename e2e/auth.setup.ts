import { expect, test as setup } from '@playwright/test';
import { execSync } from 'node:child_process';

import { E2E_EMAIL, E2E_PASSWORD, STORAGE_STATE } from './auth';

const rails = (args: string, env: Record<string, string> = {}) =>
  execSync(`bin/rails ${args}`, {
    env: { ...process.env, ...env, RAILS_ENV: 'test' },
    stdio: 'pipe',
  });

setup('sign in', async ({ page }) => {
  rails('users:upsert', {
    ADMIN_EMAIL: E2E_EMAIL,
    ADMIN_PASSWORD: E2E_PASSWORD,
  });

  await page.goto('/session/new');
  await page.getByLabel('Email address').fill(E2E_EMAIL);
  await page.getByLabel('Password').fill(E2E_PASSWORD);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByTestId('sidebar')).toBeVisible();

  await page.context().storageState({ path: STORAGE_STATE });
});
