# Playwright e2e

Browser tests against the Rails app (`RAILS_ENV=test`, port 3100). Separate from the RSpec `:js` system specs.

```sh
pnpm exec playwright install chromium   # once
pnpm build && bin/rails tailwindcss:build
RAILS_ENV=test bin/rails db:prepare
pnpm e2e            # headless
pnpm e2e:ui         # UI mode
```

Playwright starts `bin/rails server` itself, or reuses one already on `E2E_PORT` (outside CI).

## Screenshots

`pnpm screenshots` captures every ViewPrimitives primitive (`/rails/view_components/ui/*`) and a few fake-data pages (`/rails/view_components/pages/*`) into `tmp/screenshots/{primitives,pages}`. The previews live in `spec/components/previews/`; the components in `lib/view_primitives/`.
