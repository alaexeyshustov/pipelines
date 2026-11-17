---
paths:
  - "app/forms/**/*.rb"
---

# Form objects

- Live under `app/forms/<namespace>/`, e.g. `app/forms/orchestration/`.
- `#save` returns `true`/`false`, wraps multi-model writes in a transaction, and copies nested `RecordInvalid` errors onto the form's `errors`.
