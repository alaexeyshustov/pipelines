---
status: finished
---

# Extract agent resolution policy from RuntimeAgentBuilder

The cascade rule — pipeline model overrides agent defaults, which override action defaults — is core domain logic for how an agent gets configured at run time. Currently it lives inside `RuntimeAgentBuilder` alongside the mechanics of actually constructing the RubyLLM agent. Callers invoke `.build()` then inspect `.snapshot` and `.resolved_params` as two separate attributes; the cascade order is invisible at the call site. This conflation of policy and construction is why `PipelineRunner`'s test suite is 6× its implementation.

Extract the resolution policy into a dedicated module. `RuntimeAgentBuilder` becomes a thin wrapper that invokes the policy and passes the result to RubyLLM. Tests for the cascade permutations (which level wins, what happens when a level is absent) run against the policy module alone, without mocking `PipelineRunner`'s other collaborators.

## Considered options

Keep the cascade inside `RuntimeAgentBuilder`: rejected because the resolution logic and the construction logic don't change for the same reasons. Policy changes (adding a user-level override) and construction changes (switching LLM client) are orthogonal.
