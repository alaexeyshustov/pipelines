# ADR 0008: Sampler uses real tool calls with write-blocking

## Status
Accepted

## Context

The previous `StubbedAgentRun` runner extracted expected tool calls from a production chat history, built a `ToolStubRegistry`, and dynamically subclassed each tool to return pre-recorded results. This isolated prompt logic from tool result variation, but introduced significant complexity: dynamic class creation, stub registries, and a polymorphic `DatasetRecord → ActionRun` link to carry the original chat.

The stub approach also prevented measuring whether the agent calls tools correctly given real data — it could only measure whether the prompt produced the same tool-call sequence as the original run.

## Decision

The Sampler runs the agent with real tool calls. Tools that return `readonly? = false` (write tools) are wrapped with a no-op that returns a sentinel value and logs the blocked call. Read tools execute normally against live data.

`expected_tool_calls` is stored directly on `DatasetSample` (seeded from production `ActionRun` chat history at dataset-creation time, or absent for synthetic inputs). The judge compares `sample.tool_calls` against `dataset_sample.expected_tool_calls` when evaluating tool-calling behaviour.

## Trade-offs considered

**Reproducibility**: real tool results vary between runs. The stub approach produced deterministic samples. We accept this trade-off because (a) output quality metrics are more meaningful with real data, and (b) the judge evaluates tool-calling behaviour structurally (sequence, arguments) rather than result-for-result, which tolerates variation.

**Side effects**: write tools (label application, status updates) could mutate production data during sampling. The `readonly?` boundary prevents this without requiring full stubbing.

**Simplicity**: removes `ToolStubRegistry`, `ToolCallExtractor` (used only at sampling time), dynamic stub class creation, and the `recordable` polymorphism that existed solely to carry the original chat.
