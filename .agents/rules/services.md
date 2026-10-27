---
paths:
  - "app/services/**/*.rb"
---

# Services (`app/services`)

Enforced by the `App/Service*` cops (scoped to `app/services/` only):

- Public interface is exactly `def self.call(...)` delegating to `new(...).call`; no other public instance methods.
- Result objects use `Data.define`, not `Struct.new`.
- A service must not call another service's `.call`; multi-service flows belong in a job or in orchestration (`lib/orchestration`).

Not enforced, but expected: expected failures are returned in the result; unexpected ones raise.

Most domain logic lives in `lib/` (`lib/orchestration`, `lib/evaluation`), which these cops do not check; follow the style of the surrounding module there.
