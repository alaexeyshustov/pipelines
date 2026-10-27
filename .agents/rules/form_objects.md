---
paths:
  - "app/forms/**/*.rb"
---

# Form objects

- Inherit from `::BaseForm` (ActiveModel model/attributes/validations + `JsonParamsParsing`). Enforced by `App/FormObjectMustInheritBaseForm`.
- Live under `app/forms/<namespace>/`, e.g. `app/forms/orchestration/`.
- `#save` returns `true`/`false`, wraps multi-model writes in a transaction, and copies nested `RecordInvalid` errors onto the form's `errors`.
- No side effects in `#save` (jobs, LLM/API calls, emails): the controller or a service triggers those after a successful save.
