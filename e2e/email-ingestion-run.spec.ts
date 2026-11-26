import { expect, test } from '@playwright/test';
import { execSync } from 'node:child_process';

// Runs "Email Ingestion" end to end from the UI: the fixture mailbox (e2e/fixtures/mailbox.json) stands in for
// Gmail and Yahoo, and classification and embeddings go to a local Ollama. Skips when Ollama or its models are
// missing.
const PIPELINE = 'Email Ingestion';
const STEPS = [
  'List emails',
  'Classify emails',
  'Embed emails',
  'Ingest attachments',
  'Classify documents',
  'Embed documents',
];
const OLLAMA_BASE = (
  process.env.OLLAMA_API_BASE ?? 'http://localhost:11434/v1'
).replace(/\/v1\/?$/, '');
const MODELS = [
  process.env.OLLAMA_TEST_MODEL ?? 'qwen3:8b',
  process.env.OLLAMA_DECISION_MODEL ?? 'clef-flash',
  process.env.EMBEDDING_MODEL ?? 'qwen3-embedding:0.6b',
].map((model) => (model.includes(':') ? model : `${model}:latest`));

const { ADMIN_EMAIL: _email, ADMIN_PASSWORD: _password, ...seedEnv } = process.env;

const rails = (args: string) =>
  execSync(`bin/rails ${args}`, {
    env: { ...seedEnv, RAILS_ENV: 'test' },
    stdio: 'pipe',
  }).toString();

// Rows the seeds and the run commit; RSpec's transactional fixtures would not remove them.
const RESET = [
  'Embedding',
  'Tagging',
  'Document',
  'Email',
  'Email::SyncCursor',
  'Orchestration::ActionRun',
  'Orchestration::PipelineRun',
  'Orchestration::StepAction',
  'Orchestration::Step',
  'Orchestration::Pipeline',
  'Orchestration::Action',
  'Orchestration::Agent',
  'Evaluation::Dataset',
  'Subtag',
  'Tag',
]
  .map((model) => `${model}.destroy_all`)
  .join(';');

const resetData = () => rails(`runner '${RESET}'`);

const missingModels = async (): Promise<string | null> => {
  try {
    const response = await fetch(`${OLLAMA_BASE}/api/tags`);
    const { models } = (await response.json()) as { models: { name: string }[] };
    const pulled = models.map(({ name }) => name);
    const missing = MODELS.filter((model) => !pulled.includes(model));
    return missing.length ? `Ollama lacks ${missing.join(', ')}` : null;
  } catch {
    return `Ollama is not reachable at ${OLLAMA_BASE}`;
  }
};

test.describe.configure({ mode: 'serial' });
test.use({ video: 'on' });

test.beforeAll(async () => {
  const reason = await missingModels();
  test.skip(reason !== null, reason ?? '');
  resetData();
  rails('db:seed');
});

test.afterAll(resetData);

test.afterEach(async ({ page }) => {
  await page.close();
  await page.video()?.saveAs('tmp/videos/email-ingestion-run.webm');
});

test('runs the email ingestion pipeline from the UI', async ({ page }) => {
  test.setTimeout(15 * 60_000);

  await page.goto('/orchestration/pipelines');
  await page.getByRole('link', { name: PIPELINE }).click();
  await expect(page.getByRole('heading', { name: PIPELINE })).toBeVisible();

  await page.getByRole('button', { name: 'Run now' }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Gmail').check();
  await dialog.getByLabel('Yahoo').check();
  await dialog.locator('#field_date_from').fill('2026-11-01');
  await dialog.locator('#field_date_to').fill('2026-11-06');
  await dialog.getByRole('button', { name: 'Run', exact: true }).click();
  await expect(page.getByTestId('notice')).toHaveText('Pipeline run triggered.');

  await page.getByRole('link', { name: 'Run History' }).click();
  await page.getByRole('link', { name: 'Details' }).first().click();
  await expect(page.getByRole('heading', { name: /Run #\d+/ })).toBeVisible();

  // The run page does not refresh itself; reload until the run has finished.
  const header = page.getByTestId('page-header');
  const finished = header
    .getByText('Completed', { exact: true })
    .or(header.getByText('Failed', { exact: true }));
  await expect(async () => {
    await page.reload();
    await expect(finished.first()).toBeVisible({ timeout: 1_000 });
  }).toPass({ timeout: 14 * 60_000, intervals: [5_000] });

  await expect(finished.first()).toHaveText('Completed');
  const steps = page.getByTestId('step-run');
  await expect(steps).toHaveCount(STEPS.length);
  for (const [index, name] of STEPS.entries()) {
    await expect(steps.nth(index).getByTestId('step-name')).toHaveText(name);
    await expect(steps.nth(index)).toContainText('Completed');
  }

  // Model output varies, so only the shape is checked: every email and the attachment are classified and the
  // tagged ones embedded.
  const counts = JSON.parse(
    rails(
      `runner 'puts({ emails: Email.count, documents: Document.count, ` +
        `unclassified: Email.where(classification_status: %w[pending failed]).count + ` +
        `Document.where(classification_status: %w[pending failed]).count, ` +
        `unembedded: Email.tagged.without_embedding(model: LlmModels.embedding).count + ` +
        `Document.tagged.without_embedding(model: LlmModels.embedding).count }.to_json)'`,
    ).trim(),
  );
  expect(counts).toEqual({
    emails: 3,
    documents: expect.any(Number),
    unclassified: 0,
    unembedded: 0,
  });

  // Show each step's output in the video.
  for (const output of await steps.getByText('Output', { exact: true }).all()) {
    await output.click();
  }
  await page.waitForTimeout(2_000);
});
