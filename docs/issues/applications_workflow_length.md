# ApplicationsWorkflow is too long

**Status:** draft

**Source:** `lib/pipeline/applications_workflow.rb`

`Pipeline::ApplicationsWorkflow` orchestrates the end-to-end job-application email pipeline (fetch → classify → label → persist). The class covers too many sequential steps directly, requiring a `rubocop:disable Metrics/ClassLength` suppression.

**Suggested approach:** decompose each major pipeline step into a dedicated collaborator (fetcher, classifier, labeller, persister) and leave `ApplicationsWorkflow` as a thin coordinator that sequences them.
