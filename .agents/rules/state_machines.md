---
paths:
  - "app/models/**/*.rb"
---

# State machines

- Simple states: Rails `enum`. Complex workflows: AASM (currently only `Evaluation::Experiment`).
- Always pass the column explicitly: `aasm column: :status do` (enforced by `App/AasmMustSpecifyColumn`).
- No AASM callbacks for external side effects (jobs, LLM/API calls, emails). The service or job that fires the event performs them; callbacks may only normalize data or touch related records.
