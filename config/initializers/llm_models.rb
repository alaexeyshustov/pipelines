# Central registry for LLM model names. Resolution order per accessor:
#   1. Setting table (writable at runtime via the settings UI)
#   2. ENV var
#   3. Hardcoded default
#
# Callers that evaluate at class-load time (agent `model` DSL, DEFAULT_MODEL
# constants in services/jobs) cache the resolved value — a restart or class
# reload is required for those callers to pick up changes.
#
# ENV var naming note: EVALUATION_LLM_MODEL and JUDGE_LLM_MODEL pre-date this
# module and are preserved for backwards compatibility; new vars follow the
# <SUBJECT>_AGENT_MODEL convention.
# judge: must be a RubyLLM `judgment` model (gpt-6-luna; jev-latest is the fallback, see Evaluation::Judge::ModelChoice).
#
# A local model is written as "provider/model" (e.g. "ollama/qwen3") to pin its provider; call sites go through
# LlmModels.ref (ModelRef) to pass `provider:` on to RubyLLM. Hosted ids stay bare.
module LlmModels
  # A configured model id. A bare id resolves through the registry as before; "<local provider>/model" (e.g.
  # "ollama/qwen3") pins a local provider, whose models are in the registry only after a sync and may share ids
  # with other providers. Only a local provider slug counts as a prefix: the registry holds hundreds of hosted
  # OpenRouter ids like "anthropic/claude-haiku-4.5" that must keep resolving as bare ids. Checking locality
  # rather than "is this a registry id" keeps the meaning of a stored id independent of the next models sync.
  # The helpers below pass `provider:` and `assume_model_exists:` (persisted Chat records look the model up in the
  # registry even for a local provider) on to each RubyLLM entry point.
  ModelRef = Data.define(:model, :provider) do
    def self.parse(value)
      id = value.to_s.strip
      slug, model = id.split("/", 2)
      provider = slug.to_s.to_sym
      return new(model: id, provider: nil) if model.blank? || !RubyLLM::Provider.providers[provider]&.local?

      new(model:, provider:)
    end

    # The id to configure for a registry model (model pickers): "provider/model" for a local provider, so it
    # parses back to that provider; the bare registry id otherwise.
    def self.id_for(model_id, provider)
      RubyLLM::Provider.providers[provider.to_s.to_sym]&.local? ? "#{provider}/#{model_id}" : model_id
    end

    def local? = !provider.nil?

    # Agent class DSL: `LlmModels.ref(LlmModels.emails_agent).declare_on(self)`.
    def declare_on(agent_class) = agent_class.model(model, provider:, assume_model_exists: local?)

    # Agent#with_model on an instance; returns the agent (Agent#with_model returns its chat).
    def apply_to(agent)
      agent.with_model(model, provider:, assume_model_exists: local?)
      agent
    end

    # Keywords for RubyLLM.chat and Judge#judge.
    def chat_options = { model:, provider:, assume_model_exists: local? }

    # Chat#with_fallbacks takes bare ids; a pinned fallback needs a Fallback target carrying the provider.
    def fallback = provider ? RubyLLM::Fallback.new(id: model, provider:) : model
  end

  class << self
    def ref(value) = ModelRef.parse(value)

    def emails_agent  = Setting.fetch("emails_agent_model")   || ENV.fetch("EMAILS_AGENT_MODEL",  "mistral-large-latest")
    def records_agent = Setting.fetch("records_agent_model")  || ENV.fetch("RECORDS_AGENT_MODEL", "gpt-5.1")
    def evaluation    = Setting.fetch("evaluation_llm_model") || ENV.fetch("EVALUATION_LLM_MODEL", "gpt-5.4")
    # Fallback models for evaluation chats (improver, extractor, suggester), comma-separated; blank disables.
    # A different provider than `evaluation` so a provider outage is survivable (RubyLLM Chat#with_fallbacks).
    # No default for a local evaluation model: an offline run must not fall back to a hosted provider.
    def evaluation_fallbacks
      default = ref(evaluation).local? ? "" : "mistral-large-latest"
      raw = Setting.fetch("evaluation_fallback_models") || ENV.fetch("EVALUATION_FALLBACK_MODELS", default)
      raw.to_s.split(",").map(&:strip).compact_blank
    end

    def judge         = Setting.fetch("judge_llm_model")      || ENV.fetch("JUDGE_LLM_MODEL",     "gpt-6-luna")
  end
end
