import { expect, test } from '@playwright/test';
import { pages, pageUrl } from './targets';

for (const name of pages) {
  test(`page: ${name}`, async ({ page }) => {
    const response = await page.goto(pageUrl(name));
    expect(response?.ok(), `GET ${pageUrl(name)}`).toBeTruthy();
    await expect(page.locator('main')).toBeVisible();
    await page.screenshot({
      path: `tmp/screenshots/pages/${name}.png`,
      fullPage: true,
    });
  });
}

test('page: pipeline_show (delete dialog open)', async ({ page }) => {
  const response = await page.goto(pageUrl('pipeline_show'));
  expect(response?.ok()).toBeTruthy();
  await page.getByRole('button', { name: 'Delete' }).first().click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.screenshot({
    path: 'tmp/screenshots/pages/pipeline_show_dialog.png',
  });
});
