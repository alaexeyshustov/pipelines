# LLMJudgeEval is too long

**Status:** draft

**Source:** `lib/evaluation/evaluators/llm_judge_eval.rb`

`Evaluation::Evaluators::LLMJudgeEval` handles metric loading, prompt construction, judge LLM calls, response parsing, and error handling in one class, requiring a `rubocop:disable Metrics/ClassLength` suppression.

**Suggested approach:** extract prompt-building into a dedicated builder object and move response-parsing/validation into a separate parser, keeping `LLMJudgeEval` as a thin coordinator that wires them together.
