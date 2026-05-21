---
status: finished
---

# Evaluation wizard refactor and ExperimentDetailComponent extraction

## Context

`ExperimentsController` accumulates three distinct clusters of logic that violate the thin-controller rule:

1. **Multi-step wizard coordination** — `find_or_create_draft`, `step_payload`, `load_step_data`, and `create_experiment_from_draft` are private controller methods; the controller directly manages the `session[:wizard_token]` lifecycle and instantiates step-specific forms inline.
2. **WizardComponent leaking controller state** — `WizardComponent` reads `@step` and `@form` as controller instance variables from the view context instead of receiving them through its own interface. The four `renders_one` slot declarations in the component are unused.
3. **Fat `show` action** — seven instance variables (`@agent_name`, `@metrics`, `@runner_result_count`, `@per_metric_avg`, `@runner_model`, `@judge_model`, `@newer_experiment`) are all display-derived values that belong in a component, not a controller action.

## Requirements

### `Evaluation::WizardForm`

- Encapsulates `find_or_create_draft`, `step_payload`, `load_step_data`, and `create_experiment_from_draft`.
- Accepts `wizard_token:` as a plain string. The controller owns reading and writing `session[:wizard_token]`; the form never touches `session`.
- Instantiated in the controller and passed to `WizardComponent`.

### `Evaluation::WizardComponent`

- Accepts `form: <WizardForm>` and `current_step: <Integer>`.
- Decides which step sub-component to render internally — no `case`/`when` dispatch in the ERB template.
- `new.html.erb` stays unconditional: `render Evaluation::WizardComponent.new(current_step: @step, form: @wizard_form)`.
- Remove the four unused `renders_one` slot declarations.

### `Evaluation::ExperimentDetailComponent`

- New ViewComponent that accepts `experiment:` and exposes all derived display values as component methods: `agent_name`, `metrics`, `runner_result_count`, `per_metric_avg`, `runner_model`, `judge_model`, `newer_experiment`.
- `ExperimentsController#show` assigns only `@experiment`; the component computes everything else.

## Out of scope

- `Orchestration::PipelinesController#run` and `Orchestration::StepActionsController#create` form-object TODOs — deferred.
