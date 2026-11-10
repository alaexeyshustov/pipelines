# Local models (Ollama)

RubyLLM's Ollama provider lets agents and evaluation chats run against a local model instead of a hosted one.

## Setup

1. Run Ollama and pull a model: `ollama pull qwen3`.
2. Set `OLLAMA_API_BASE=http://localhost:11434/v1` (`OLLAMA_API_KEY` only behind an authenticating proxy). Without it the Ollama provider stays unconfigured and nothing changes.
3. Point a model setting at it as `ollama/<model>`, e.g. `EMAILS_AGENT_MODEL=ollama/qwen3`, `EVALUATION_LLM_MODEL=ollama/qwen3:8b`, or an agent/pipeline model of `ollama/qwen3`.

## Model ids

Any configured model id (`LlmModels.*`, the Setting table, `Orchestration::Agent#model`, pipeline and experiment models) may name a local model as `provider/model`. `LlmModels.ref` parses it into an `LlmModels::ModelRef`, whose helpers pass `provider:` and `assume_model_exists:` to RubyLLM: `declare_on` (the agent `model` DSL), `apply_to` (`Agent#with_model`), `chat_options` (`RubyLLM.chat`, `Judge#judge`) and `fallback` (`fallbacks`).

- Only a **local** RubyLLM provider slug (`ollama`, `gpustack`) counts as a prefix. Every other id stays bare and resolves through the registry as before, including the hosted OpenRouter ids that contain a slash (`anthropic/claude-haiku-4.5`, `openai/gpt-4o`, `meta-llama/llama-3`). Hosted providers cannot be pinned this way; the rule depends only on the slug, not on what the last models sync added.
- The split is on the first `/`, so Ollama tags and paths survive (`ollama/qwen3:8b`, `ollama/hf.co/org/model`).
- Model pickers (agent form, experiment wizard) offer synced local models as `ollama/<model>`, so a picked model parses back to its provider. A bare Ollama id still works after a sync but is ambiguous when another provider lists the same id.
- A local provider's model is assumed to exist (`assume_model_exists: true`), so no sync is needed. Capabilities are then assumed too; a sync records what Ollama reports (`/api/show`).

## Model choice

Agents need tool calling and structured output. Ollama reports `tools` only for models that support it (RubyLLM maps it to `function_calling`). Recommended: Qwen3 (8B or larger), Llama 3.1+. Expect weaker results and lower eval scores from small models.

## Evaluation caveats

- **Judge (not offline yet)**: `Evaluation::Judge::ModelChoice` needs a `judgment` model. A local model qualifies only if a sync recorded Ollama's `decision` capability. Otherwise grading **falls back to `LlmModels.judge` and then the hosted `jev-latest`**, so experiments still send each sample to a hosted provider. A fully offline run needs a local decision model; skipping or locally judging is a follow-up.
- **Fallbacks**: `LlmModels.evaluation_fallbacks` defaults to none when `EVALUATION_LLM_MODEL` is local (the hosted `mistral-large-latest` otherwise). An explicit `EVALUATION_FALLBACK_MODELS` or Setting still wins; keep it blank for offline runs.
- **Cost**: Ollama models have no pricing. Their usage rows carry tokens and no cost; `ExperimentUsageQuery` and monitoring count them as $0.

## Tests against Ollama

`LLM_TEST_BACKEND=ollama bundle exec rspec` runs only the `:llm`-tagged specs against a local Ollama (`OLLAMA_API_BASE`, default `http://localhost:11434/v1`; `OLLAMA_TEST_MODEL`, default `qwen3`). See `spec/support/llm_test_backend.rb`.

- `LlmModels.*` (agents, evaluation chats, judge) are routed to `ollama/$OLLAMA_TEST_MODEL` before the app loads, and `EVALUATION_FALLBACK_MODELS` is forced blank whatever your env says. Tagged specs use `LlmTestBackend.model_for(...)` for models they set themselves.
- Tagged: the email agent specs, the evaluation chats (prompt improver, metric extractor/suggester, synthetic dataset job, usage scope), the grader, the pipeline runner/lifecycle specs and the Ollama round-trip. The judge example skips while the judge falls back to a hosted model (see above). Untagged: specs that assert hosted request bodies, stub failure or malformed responses, or run agents whose tools write to the database or mailbox (records agents).
- Ollama requests bypass VCR and WebMock. A hosted LLM request raises instead of replaying or recording a cassette; other cassettes (Gmail, GitHub) still replay.
- An unreachable Ollama, a model that is not pulled, or one that rejects structured output skips the examples with the reason. Some models reject it outright (e.g. `qwen3.5:9b` on Ollama's MLX runner answers `501 structured output is unavailable`).
- Assertions on model output check only the shape in this mode (`LlmTestBackend.live?`).
- Default `bundle exec rspec` is unchanged and offline: Ollama gets an unroutable base URL and the round-trip spec stubs it.
