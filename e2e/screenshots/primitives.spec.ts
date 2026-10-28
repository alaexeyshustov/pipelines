import { expect, test, type Page } from '@playwright/test';
import { primitiveUrl, primitives } from './targets';

const out = (name: string) => `tmp/screenshots/primitives/${name}.png`;

async function open(page: Page, name: string) {
  const response = await page.goto(primitiveUrl(name));
  expect(response?.ok(), `GET ${primitiveUrl(name)}`).toBeTruthy();
  const root = page.locator('[data-preview-root]');
  await expect(root).toBeVisible();
  return root;
}

for (const name of primitives) {
  test(`primitive: ${name}`, async ({ page }) => {
    const root = await open(page, name);
    await root.screenshot({ path: out(name) });
  });
}

test('primitive: dialog (open)', async ({ page }) => {
  await open(page, 'dialog');
  await page.getByRole('button', { name: 'Open dialog' }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.screenshot({ path: out('dialog_open') });
});

test('primitive: tabs (second tab)', async ({ page }) => {
  const root = await open(page, 'tabs');
  await page.getByRole('tab', { name: 'Steps' }).click();
  await expect(page.getByText('Steps tab content')).toBeVisible();
  await root.screenshot({ path: out('tabs_second') });
});

test('primitive: sidebar (collapsed)', async ({ page }) => {
  const root = await open(page, 'sidebar');
  await page.locator('[data-sidebar-target="toggle"]').click();
  // The rail animates its width (duration-300); wait for w-16 (64px) before capturing.
  await expect
    .poll(async () => (await page.locator('aside').boundingBox())?.width)
    .toBe(64);
  await root.screenshot({ path: out('sidebar_collapsed') });
});
