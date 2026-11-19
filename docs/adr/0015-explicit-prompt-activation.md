# ADR 0015: Explicit prompt activation

## Status
Accepted (GH #301, part of #240 SEC-06)

## Context

`Evaluation::ActivePromptResolver` served the newest `Evaluation::Prompt` for an agent, so any new version (including an unreviewed draft from `PromptImprover` or a wizard fork) went live on the next pipeline run. The Activate button only set a `metadata` JSON flag that nothing at runtime read, and the flag was queried with `json_extract` in a few places.

## Decision

- **Column, not metadata.** `evaluation_prompts.active` (boolean, default false) with a partial unique index on `name WHERE active`, so the database allows at most one live version per agent. `activated_at` is set on every activation and never cleared; it records "was live before".
- **Runtime rule.** The resolver returns the active version's `system_prompt`. With none active it returns nil and the agent's own prompt (`Orchestration::Agent#prompt`) applies. The fallback reads the `Orchestration::Agent` model, not `AgentCatalog`, because a domain model must not depend on the application layer.
- **Guards.** `Prompt#activate!` itself has no guard (it deactivates the other versions and stamps `activated_at` in one transaction). Callers check: the experiment's Activate requires `experiment.completed?`; the Prompts page requires `Prompt#activatable?` (`activated_at` present or a completed experiment), so a rollback to an earlier version needs no new experiment. `deactivate!` is a no-op on an inactive version.
- **Immutability.** A `Prompt` is an immutable snapshot except for `active` and `activated_at`.
- **Backfill.** The migration marks the newest version per agent active (ties by highest id) and stamps `activated_at`, then strips the legacy `$.active` key from valid JSON metadata. This knowingly keeps today's newest draft live so the deploy changes nothing; operators review afterwards.
- **UI.** The Prompts page lists every version, so it carries the Active column and Activate/Deactivate. Experiment and comparison pages diff against the active version, or an `AgentDefaultPrompt` value object labelled "Agent default".

## Consequences

- New and improved prompts stay inactive until someone activates them after an experiment.
- A deploy-time review of the backfilled versions is needed.
- `load_samples` for the improvement agent wraps sample data in `<untrusted_sample>` tags (escaped, truncated to 4,000 characters, at most 20 samples) as a separate hardening in the same change.
