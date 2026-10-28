import { expect, test } from '@playwright/test';

test('renders the app layout with the sidebar', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByTestId('sidebar')).toBeVisible();
});
