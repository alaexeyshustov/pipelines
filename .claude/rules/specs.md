---
paths:
  - "spec/*.rb"
  - "spec/**/*.rb"
---

# Writing Good Specs

Tests verify behavior through public interfaces. Prefer realistic data, clear failures, and focused assertions.

## Core Principles

1. **Test behavior, not implementation details** – Prefer observable outcomes over private-method or callback-level assertions.
2. **Prefer real collaborators in integration-style specs** - Request and system specs should usually use real application objects. Use WebMock/VCR for external APIs and stub only true boundaries.
3. **Pristine test output** – Capture and verify expected errors, don't let them pollute output
4. **All failures are your responsibility** – Treat failing specs, even pre-existing ones, as actionable until understood.
5. **System specs test through the UI** – See the System Specs section below.
6. **Prefer explicit expectations** – Matcher-heavy one-liners (including many shoulda-style assertions) often hide intent and failure context.
7. **Do not use `double()`** – Stub external boundaries, not the behavior you are trying to verify. Use real objects or test doubles that mimic real behavior (e.g., `instance_double` with verified methods).
8. **Use `stub_const` for anonymous/dynamic classes in tests** - never inline anonymous classes that need deserialization
9. **When setting up specs with doubles/spies, verify keyword arguments match the actual method signatures**

## Spec Types

| Type      | Location           | Use For                                                                                    |
|-----------|--------------------|--------------------------------------------------------------------------------------------|
| Request   | `spec/requests/`   | Single action (CRUD, redirects).                                                           |
| System    | `spec/system/`     | Multi-step user flows through the UI. Every action via Capybara (clicks, fills, navigates) |
| Model     | `spec/models/`     | Public interface                                                                           |
| Services  | `spec/services/`   | ALL services                                                                               |
| Component | `spec/components/` | ViewComponent rendering                                                                    |

## Factory Rules

- **Explicit attributes** - `create(:interview, status: :screening)` not `create(:interview)`
- **Use traits** - `:published`, `:draft` for variations
- **`let` by default** - `let!` only when record must exist before test
- **Create in final state** - No `update!` in before blocks

## Common Mistakes

1. **Over-mocking** – Stub external boundaries, not the behavior you are trying to verify.
2. **`sleep` in system specs** – Use Capybara's waiting behavior.
3. **Deleting or sidelining failing tests** - Fix the root cause.
4. **Bypassing UI behavior in system specs** – If the test claims to cover the UI, drive the key interaction through the browser.

## System Specs (Non-Negotiable)

System specs cover the browser-visible flow. Factory setup and an initial `visit` are fine; the interaction being verified should still happen through the UI.

| User does this     | Prefer this in the spec                | Avoid this shortcut             |
|--------------------|----------------------------------------|---------------------------------|
| Navigates via menu | `click_link('Reviews')`                | Jump straight to the end state  |
| Confirms a dialog  | `accept_confirm { click_button(...) }` | Skip the dialog entirely        |
| Fills a form       | `fill_in 'Name', with: 'value'`        | Create the outcome directly     |

If a UI interaction is hard to automate (confirmation dialogs, JS-heavy flows), prefer Capybara's tools (`accept_confirm`, `accept_alert`, `execute_script`) over bypassing the interaction.

**Remember:** Tests should make behavior obvious. Use the lightest spec type that still verifies the behavior you care about.

## References
- [RSpec](https://rspec.info/) – Most popular testing framework for Ruby. Provides a rich DSL for writing expressive tests. Prefer RSpec for new test suites.
- [Better Specs](https://www.betterspecs.org/) – Best practices for writing good tests in Ruby
- [Capybara](https://github.com/teamcapybara/capybara) – Acceptance testing library for web applications. Simulates browser interactions via a DSL used by system specs.
