---
paths:
  - "spec/**/*.rb"
---

# Specs

- When stubbing, keep keyword arguments matching the real method signatures.
- Factories: explicit attributes (`create(:interview, status: :screening)`), traits for variants, `let` by default (`let!` only when the record must exist up front).
- System specs drive the verified interaction through the UI (`click_link`, `fill_in`, `accept_confirm`).
- Where specs live: `spec/lib/` for `lib/` code (most domain logic), `spec/services/` for `app/services`, `spec/requests/` for single actions, `spec/system/` for multi-step UI flows, `spec/components/` for components.
- N+1 queries fail specs (Prosopite, `spec/support/prosopite.rb`): fix them, or allowlist a method-scoped pattern there with a one-line reason.
