---
paths:
  - "app/services/**/*.rb"
---

# Services (`app/services`)

Expected failures are returned in the result; unexpected ones raise.

Services may call other services for synchronous domain logic and propagate their results. Async or multi-step pipeline flows belong in a job or in orchestration (`lib/orchestration`).

Most domain logic lives in `lib/` (`lib/orchestration`, `lib/evaluation`); follow the style of the surrounding module there.
