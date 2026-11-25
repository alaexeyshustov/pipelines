import { defineConfig, devices } from '@playwright/test';
import { STORAGE_STATE } from './e2e/auth';

const port = Number(process.env.E2E_PORT ?? 3100);
const baseURL = `http://127.0.0.1:${port}`;
const ollamaModel = `ollama/${process.env.OLLAMA_TEST_MODEL ?? 'qwen3:8b'}`;
// Tags::Classifier uses RubyLLM::Judge, which needs a decision model (Clef), not a chat model.
const ollamaDecisionModel = `ollama/${process.env.OLLAMA_DECISION_MODEL ?? 'clef-flash'}`;

export default defineConfig({
  testDir: './e2e',
  outputDir: './tmp/playwright/results',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI
    ? [
        ['github'],
        ['html', { open: 'never', outputFolder: 'tmp/playwright/report' }],
      ]
    : 'list',
  use: {
    baseURL,
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'setup',
      testMatch: /auth\.setup\.ts/,
      teardown: 'teardown',
    },
    { name: 'teardown', testMatch: /auth\.teardown\.ts/ },
    {
      name: 'chromium',
      testIgnore: /screenshots\//,
      dependencies: ['setup'],
      use: { ...devices['Desktop Chrome'], storageState: STORAGE_STATE },
    },
    {
      name: 'screenshots',
      testMatch: /screenshots\/.*\.spec\.ts/,
      fullyParallel: false,
      dependencies: ['setup'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: STORAGE_STATE,
        viewport: { width: 1440, height: 900 },
        deviceScaleFactor: 2,
      },
    },
  ],
  webServer: {
    command: `bin/rails server -e test -b 127.0.0.1 -p ${port}`,
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    // Jobs run in the server (async adapter), mail comes from the fixture mailbox and the LLM calls go to a local
    // Ollama (see e2e/README.md).
    env: {
      E2E: '1',
      EMAIL_FIXTURES: 'e2e/fixtures/mailbox.json',
      OLLAMA_API_BASE: process.env.OLLAMA_API_BASE ?? 'http://localhost:11434/v1',
      EMAILS_AGENT_MODEL: ollamaModel,
      JUDGE_LLM_MODEL: ollamaDecisionModel,
    },
  },
});
