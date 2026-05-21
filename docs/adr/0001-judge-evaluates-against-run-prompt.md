---
status: finished
---

# Judge evaluates against the prompt the run actually used

When `LLMJudgeEval` scores an agent's output it needs a reference point for "Agent Instructions." Two options exist: use the prompt version the runner actually executed with (stored on `leva_runner_results.prompt_id`), or always fetch the current-latest prompt version for that agent.

We chose the run's own prompt. A score measures "how well did this prompt version perform?" — not "does the output from this old run satisfy today's rules?" Using the latest creates a moving target: every new improvement cycle makes prior experiments look worse against stricter criteria, poisoning the improvement signal. This was the primary cause of monotonically falling scores observed in the ClassifyAgent improvement loop (May 2026): the agent output was stable but the judge's reference kept ratcheting up.

The rejected alternative (latest-prompt evaluation) would be useful if you wanted to detect regressions — "does old output still satisfy new rules?" — but that is a distinct use case that deserves a separate evaluation path, not a side-effect of the normal improvement loop.
