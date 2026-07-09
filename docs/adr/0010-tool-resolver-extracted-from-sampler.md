# ADR 0010: Extract `Orchestration::ToolResolver` from `Evaluation::Sampler`

## Status
Accepted

## Context

`Evaluation::Sampler` (`app/services/evaluation/sampler.rb`) resolved an agent's tool classes itself: given configured tool name strings, it validated each against `Orchestration::Agent::ALLOWED_TOOL_NAMESPACES` and constantized it, falling back to the agent class's own declared `.tools` when none were configured. This is an orchestration-layer security check (the tool-namespace allowlist), not an evaluation concern, and it was one of three near-identical copies of that check in the codebase (the others being `Orchestration::Agent`'s own validation and `Orchestration::AgentResolutionPolicy#resolve_tool_class`).

The broader ask was to move orchestration logic living in `app/services` into `lib/orchestration`, leaving `app/services` with thin MVC-integration/CRUD/command services. A first proposal extracted three collaborators (agent lookup, tool resolution, write-tool blocking) into `lib/orchestration`. Review (Planner → Architect → Critic consensus) rejected that scope: the agent-lookup collaborator had no caller besides `Sampler` and collided in name with the existing `Orchestration::AgentResolutionPolicy`; the write-blocking wrapper encodes a sampling-specific safety concern (the `WRITE_BLOCKED_SENTINEL` sentinel, tool-call trace shaping) that does not belong in `lib/orchestration` any more than the rejected single-facade alternative did — moving it would have reproduced the same evaluation-concept leak the facade approach was rejected for.

## Decision

Extract only `Orchestration::ToolResolver` (`lib/orchestration/tool_resolver.rb`) — `Orchestration::ToolResolver.new(agent:).resolve`, an instance method matching this subsystem's existing convention (`AgentResolutionPolicy#resolve`, `RuntimeAgentBuilder#build`), not the `app/services` `.call` convention. It owns the namespace-validated tool constantization and the agent-class `.tools` fallback, moved verbatim from `Sampler`.

`Evaluation::Sampler` composes it (`Orchestration::ToolResolver.new(agent: agent_record).resolve` inside `build_agent`) and keeps everything else: agent/action lookup, write-tool blocking, tool-call trace capture, and `Evaluation::Sample` persistence. The public interface `Sampler.call(experiment:, dataset_sample:, prompt:)` is unchanged (it is load-bearing — called from `Evaluation::SamplingJob`).

This is a **partial** result relative to the original "app/services should be thin CRUD/command services only" framing: `Sampler` still references `Orchestration::AgentResolutionPolicy`, `Orchestration::RuntimeAgentBuilder`, `Orchestration::Agent`, and `Orchestration::Action` after this change, because it legitimately composes orchestration primitives to do evaluation-domain work (persisting samples, shaping tool-call traces for the judge). Full decoupling would require either relocating `Sampler` wholesale into `lib/` — the wrong fit, since it owns `ActiveRecord` persistence and eval-specific trace shaping — or rebuilding the single-facade approach already rejected above. This trade-off is intentional, not an oversight.

## Trade-offs considered

**Extraction scope (1 primitive vs. 3, vs. none)**: extracting only `ToolResolver` removes orchestration tool-namespace validation from the eval layer — a real coupling-direction improvement — without minting single-caller abstractions (agent lookup) or leaking eval-specific concepts into `lib/orchestration` (write-blocking). It does not reduce the total number of namespace-validation copies in the codebase (still three: `Orchestration::Agent`, `AgentResolutionPolicy`, `ToolResolver`) — it relocates the eval layer's copy, it does not centralize ownership of the allowlist.

**Deferred: converging `AgentResolutionPolicy#resolve_tool_class` onto `ToolResolver`**: not done here. The policy's version has a `Class`-passthrough and a richer error message that the moved code lacks, and it sits on the `PipelineRunner` execution path, which this change's test scope does not cover. Converging them needs its own red-first spec plan guarding those two behaviors explicitly.

**Message preservation**: agent-lookup error messages ("No agent found for experiment", "No action found for agent ...") were not moved and are therefore unchanged by construction. The three tool-resolution error messages that did move ("... is outside allowed namespaces", "Unknown tool class: ...", "... has no configured tools") had zero prior spec coverage under `Sampler`; they are now pinned by `spec/lib/orchestration/tool_resolver_spec.rb`.
