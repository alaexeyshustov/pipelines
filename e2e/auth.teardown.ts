import { test as teardown } from '@playwright/test';
import { execSync } from 'node:child_process';
import { E2E_EMAIL } from './auth';

// The test database is shared with RSpec: leave no login behind.
teardown('remove the login', () => {
  execSync(
    `bin/rails runner 'User.where(email_address: "${E2E_EMAIL}").destroy_all'`,
    { env: { ...process.env, RAILS_ENV: 'test' }, stdio: 'pipe' },
  );
});
