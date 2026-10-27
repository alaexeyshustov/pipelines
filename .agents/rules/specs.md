---
paths:
  - "spec/**/*.rb"
---

# Specs

- No `double`/`spy` (enforced by `App/NoTestDoubles`): use real objects, `instance_double` with verified methods, or WebMock/VCR at external boundaries.
- Use `stub_const` for anonymous or dynamic classes; never inline anonymous classes that need deserialization.
- When stubbing, keep keyword arguments matching the real method signatures.
- Factories: explicit attributes (`create(:interview, status: :screening)`), traits for variants, `let` by default (`let!` only when the record must exist up front), and create records in their final state rather than `update!` in `before`.
- System specs drive the verified interaction through the UI (`click_link`, `fill_in`, `accept_confirm`); no `sleep` (enforced by `App/NoSleepInSystemSpecs`).
- Where specs live: `spec/lib/` for `lib/` code (most domain logic), `spec/services/` for `app/services`, `spec/requests/` for single actions, `spec/system/` for multi-step UI flows, `spec/components/` for components.
