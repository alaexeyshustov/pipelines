import { expect, test } from '@playwright/test';
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const PIPELINE = 'Applications Workflow';
const STEP_COUNT = 10;

const rails = (args: string) =>
  execSync(`bin/rails ${args}`, {
    env: { ...process.env, RAILS_ENV: 'test' },
    stdio: 'pipe',
  });

// The seeds commit rows, and RSpec's transactional fixtures would not remove them.
const RESET = [
  'Orchestration::ActionRun',
  'Orchestration::PipelineRun',
  'Orchestration::StepAction',
  'Orchestration::Step',
  'Orchestration::Pipeline',
  'Orchestration::Action',
  'Orchestration::Agent',
  'Evaluation::Dataset',
]
  .map((model) => `${model}.destroy_all`)
  .join(';');

const resetData = () => rails(`runner '${RESET}'`);

test.describe.configure({ mode: 'serial' });
test.use({ video: 'on' });

test.beforeAll(() => {
  resetData();
  rails('db:seed');
});

test.afterAll(resetData);

test.afterEach(async ({ page }) => {
  await page.close();
  await page.video()?.saveAs('tmp/videos/pipeline-export-import.webm');
});

test('exports the seeded pipeline, deletes it and imports it back', async ({
  page,
}, testInfo) => {
  await page.goto('/orchestration/pipelines');
  await page.getByRole('link', { name: PIPELINE }).click();
  await expect(page.getByRole('heading', { name: PIPELINE })).toBeVisible();

  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('link', { name: 'Export', exact: true }).click(),
  ]);
  const exportPath = testInfo.outputPath('pipeline.json');
  await download.saveAs(exportPath);

  const exported = JSON.parse(readFileSync(exportPath, 'utf-8'));
  expect(exported.format).toBe('pipeline_export');
  expect(exported.pipelines).toHaveLength(1);
  expect(exported.pipelines[0].name).toBe(PIPELINE);
  expect(exported.pipelines[0].steps).toHaveLength(STEP_COUNT);

  await page.getByRole('button', { name: 'Delete' }).first().click();
  await page.getByRole('button', { name: 'Yes, delete' }).click();
  await expect(page).toHaveURL(/\/orchestration\/pipelines$/);
  await expect(page.getByRole('link', { name: PIPELINE })).toHaveCount(0);

  await page.locator('input[type=file]').setInputFiles(exportPath);
  await page.getByRole('button', { name: 'Import', exact: true }).click();

  await expect(page.getByTestId('notice')).toHaveText(
    `Imported (disabled): ${PIPELINE}.`,
  );
  const row = page.getByRole('row', { name: new RegExp(PIPELINE) });
  await expect(row).toContainText('Disabled');
  await expect(row).toContainText(String(STEP_COUNT));

  await page.getByRole('link', { name: PIPELINE }).click();
  await expect(page.getByRole('heading', { name: PIPELINE })).toBeVisible();
  await expect(page.getByText('Disabled').first()).toBeVisible();
});
