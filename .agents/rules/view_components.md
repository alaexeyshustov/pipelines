---
paths:
  - "app/components/**/*"
  - "spec/components/**/*.rb"
---

# ViewComponents

- Every component has a preview under `spec/components/previews/` (enforced by `App/ComponentMustHavePreview`).
- No `Current` inside components; inject values through the constructor (enforced by `App/NoCurrentInComponent`).
- No ActiveRecord queries in components; callers pass loaded data.
- Generic design-system pieces go in `UI::` (`app/components/ui/`); domain components go in their subsystem namespace (`Orchestration::`, `Evaluation::`, …).
- Logic belongs in the `.rb` class; templates only call methods.
- Prefer exposing child components as slots (`renders_one`/`renders_many`) over `render Child.new` in a template. Not enforced yet; existing exceptions: `orchestration/step_action_editor_component`, `input_mapping_component`, `schema_builder_component`.
- Use variants (`variant: :primary`) rather than passing through CSS classes.
