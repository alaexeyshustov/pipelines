# ADR 0008: Sampler uses real tool calls with write-blocking

## Status
Accepted

## Context

The previous `StubbedAgentRun` runner extracted expected tool calls from a production chat history, built a `ToolStubRegistry`, and dynamically subclassed each tool to return pre-recorded results. This isolated prompt logic from tool result variation, but introduced significant complexity: dynamic class creation, stub registries, and a polymorphic `DatasetRecord → ActionRun` link to carry the original chat.

The stub approach also prevented measuring whether the agent calls tools correctly given real data — it could only measure whether the prompt produced the same tool-call sequence as the original run.

## Decision

The Sampler runs the agent with real tool calls. Tools that return `readonly? = false` (write tools) are wrapped with a no-op that returns a sentinel value and logs the blocked call. Read tools execute normally against live data.

`expected_tool_calls` is stored directly on `DatasetSample` (seeded from production `ActionRun` chat history at dataset-creation time, or absent for synthetic inputs). The judge (`Evaluation::Grader`, a native `RubyLLM::Judge`, see [ADR 0012](0012-native-rubyllm-evaluation.md)) receives `sample.tool_calls` and `dataset_sample.expected_tool_calls` in its input and grades tool-calling behaviour with the agent's metrics; the tool-calling dimension is omitted when `expected_tool_calls` is nil.

## Trade-offs considered

**Reproducibility**: real tool results vary between runs. The stub approach produced deterministic samples. We accept this trade-off because (a) output quality metrics are more meaningful with real data, and (b) the judge evaluates tool-calling behaviour structurally (sequence, arguments) rather than result-for-result, which tolerates variation.

**Native execution**: since GH #194 the sampler runs the agent as the body of a native `RubyLLM::Evaluation` (`evaluator false`) and builds the persisted trace from the captured `Evidence` (assistant tool calls paired with tool-role messages). Write-tool blocking is unchanged and still happens inside `perform`, because the tool classes are wrapped before the agent is built.

**Side effects**: write tools (label application, status updates) could mutate production data during sampling. The `readonly?` boundary prevents this without requiring full stubbing.

**Simplicity**: removes `ToolStubRegistry`, `ToolCallExtractor` (used only at sampling time), dynamic stub class creation, and the `recordable` polymorphism that existed solely to carry the original chat.
