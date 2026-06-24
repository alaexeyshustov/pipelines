# Plan: Custom RuboCop Cops for Project Rules

Rewrite the `.claude/rules/` guidelines as enforceable RuboCop custom cops. Each cop maps to a structural/syntactic rule that the linter can verify without runtime or type information.

## Location

All cops live in `lib/rubocop/cop/app/` and are loaded via `.rubocop.yml`.

---

## Cops to Implement

### Services (`app/services/**/*.rb`)

| Cop | Rule |
|-----|------|
| `App/ServiceMustHaveClassCall` | Every class in `app/services/` must define `def self.call` |
| `App/ServiceMustHaveInstanceCall` | Every class in `app/services/` must define `def call` |
| `App/ServiceSinglePublicMethod` | Only `call` (and `initialize`) may be public instance methods; flag any others |
| `App/ServiceResultMustUseDataDefine` | If a `Result` constant is defined inside a service, it must use `Data.define`, not `Struct.new` |
| `App/ServiceMustNotCallService` | Services must not call another service's `.call` or `#call` inside their own `call` method. Services coordinate models — multi-service orchestration belongs in a job or a dedicated orchestration service. Detection: flag `SomeClass.call(` or `SomeClass.new(...).call` where `SomeClass` resolves to a known service (path-based heuristic: constant ends in a verb and is autoloaded from `app/services/`). |

### Form Objects (`app/forms/**/*.rb`)

| Cop | Rule |
|-----|------|
| `App/FormObjectMustIncludeActiveModel` | Classes in `app/forms/` must `include ActiveModel::Model` |

### Specs (`spec/**/*.rb`)

| Cop | Rule |
|-----|------|
| `App/NoTestDoubles` | Forbid `double(`, `instance_double(`, `spy(` in all spec files; use real objects or fake implementations |
| `App/NoSleepInSystemSpecs` | Flag `sleep` calls in `spec/system/` |

### Models — State Machines (`app/models/**/*.rb`)

| Cop | Rule |
|-----|------|
| `App/AasmMustSpecifyColumn` | `aasm` blocks must include the `column:` keyword argument |

### View Components (`app/components/**/*.rb`)

| Cop | Rule |
|-----|------|
| `App/NoCurrentInComponent` | Flag any `Current.` reference inside component `.rb` files; current user must be injected explicitly |
| `App/ComponentMustHavePreview` | Each `*_component.rb` must have a corresponding `*_component_preview.rb` under `spec/components/previews/` |

### Jobs (`app/jobs/**/*.rb`)

| Cop | Rule |
|-----|------|
| `App/NoAllEachInJob` | Flag `.all.each` inside job classes; enforce `find_each` |

### Helpers (`app/helpers/**/*.rb`)

| Cop | Rule |
|-----|------|
| `App/NoHtmlBuildingInHelper` | Flag `content_tag`, `tag.`, `concat` usage in helpers; HTML structure belongs in ViewComponents |

---

## Implementation Notes

- Use `include RuboCop::Cop::AutocorrectLogic` only where an autocorrect is obvious and safe (e.g., `Struct.new` → `Data.define`).
- Path-scoped cops should use `def on_class` with an early `return unless relevant_file?` guard that checks `processed_source.path`.
- `App/ServiceMustNotCallService` is the hardest cop: use a heuristic — inside `app/services/`, flag any send node where the receiver is a constant and the method is `:call`, unless it is `self`.
- Register cops in `lib/rubocop/cop/app_cops.rb` and require it from `.rubocop.yml` via `require`.

---

## Rollout Order

1. Easiest structural cops first: `ServiceMustHaveClassCall`, `ServiceMustHaveInstanceCall`, `FormObject*`, `NoTestDoubles`, `AasmMustSpecifyColumn`
2. Medium: `ServiceSinglePublicMethod`, `NoCurrentInComponent`, `NoAllEachInJob`, `NoHtmlBuildingInHelper`, `NoSleepInSystemSpecs`
3. Hardest / most heuristic: `ServiceMustNotCallService`, `ComponentMustHavePreview`, `ServiceResultMustUseDataDefine`
