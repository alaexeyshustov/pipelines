# Remove SyntheticDatasetJob — use real data only

**Status:** draft

**Source:** `app/jobs/evaluation/synthetic_dataset_job.rb`

`Evaluation::SyntheticDatasetJob` generates fake training samples via an LLM when real labelled data is unavailable. The TODO marks it as a temporary crutch: once real evaluation datasets are in place this job should be retired entirely, because synthetic data introduces noise and can mask model weaknesses that only surface on production inputs.

**Suggested approach:** confirm that every evaluation pipeline that references `SyntheticDatasetJob` has a real-data replacement, then delete the job and its enqueue sites.
