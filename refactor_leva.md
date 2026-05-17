Things to refactor:
- rename all `leva_` tables in db to `evaluation_`, rename all Leva:: models to Evaluation::
- rename Orchestration::Prompt to Evaluation::Prompt
- add output_schema column to Evaluation::Prompt
- when starting an experiment, copy prompt and output_schema from an Orchestation::Agent to Evaluation::Prompt
- add evaluation_model and sample_model to experiment, add UI fields to choose them on the experiment start page
- remove hardcoded `ENV.fetch("DEFAULT_MODEL")` and replace with experiment.evaluation_model or experiment.sample_model as appropriate