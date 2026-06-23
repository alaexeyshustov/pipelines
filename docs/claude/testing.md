# Testing workflow

Use true TDD for code changes: write and run the failing example first, implement the change, then rerun the targeted spec.

- After Ruby or spec changes, run `bundle exec rubocop -a`.
- Rerun the targeted spec file with `bundle exec rspec path/to/spec_file.rb`.
- If the change also touches RBS, follow the checks in [Type signatures](type-signatures.md).
- For deeper spec conventions, see [.claude/rules/specs.md](../../.claude/rules/specs.md).

## E2E and system specs

The project has two E2E test layers:

**Layer A — UI system spec** (`spec/system/`): Drives the browser via Cuprite (headless Chrome). Mistral is stubbed with a hand-written WebMock response — no VCR cassette. Run with: `bundle exec rspec spec/system/`.

**Layer B — Runner integration spec** (`spec/integration/`): Calls `Orchestration::PipelineRunner` directly with a real Mistral HTTP call replayed from a VCR cassette. Run with: `bundle exec rspec spec/integration/`.

### Re-recording the integration cassette

```bash
rm spec/cassettes/orchestration/pipeline_runner/classify_only.yml
RECORD_VCR=1 MISTRAL_API_KEY=$YOUR_KEY \
  bundle exec rspec spec/integration/orchestration/pipeline_runner_integration_spec.rb
```

`record: :all` overwrites every interaction idempotently. Never set `RECORD_VCR=1` in CI — cassettes must replay offline.

### Cuprite in CI

The RSpec job in `.github/workflows/ci.yml` installs Chrome via `browser-actions/setup-chrome@v1`. System specs require Chrome to be present. `WebMock.disable_net_connect!(allow_localhost: true)` keeps outbound HTTP blocked while allowing Cuprite to reach the Puma test server on `127.0.0.1`.
