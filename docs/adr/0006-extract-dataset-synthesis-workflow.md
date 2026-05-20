---
status: proposed
---

# Extract dataset synthesis workflow from SyntheticDatasetJob

`SyntheticDatasetJob` chains seven steps: fetch system prompt → fetch few-shot samples → build user message → call LLM → parse JSON → create dataset records → update wizard draft status. All of that lives inside the job. The workflow cannot be invoked without enqueuing, cannot be tested synchronously, and cannot be reused if a second entry point (a manual trigger, an API action) ever needs the same flow.

Extract the workflow into a dedicated service. The job's only responsibility becomes enqueuing and handling job-infrastructure errors. The service can be tested synchronously without job infrastructure and called from any entry point.
