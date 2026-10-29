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
module LlmModels
  class << self
    def emails_agent  = Setting.fetch("emails_agent_model")   || ENV.fetch("EMAILS_AGENT_MODEL",  "mistral-large-latest")
    def records_agent = Setting.fetch("records_agent_model")  || ENV.fetch("RECORDS_AGENT_MODEL", "gpt-5.1")
    def evaluation    = Setting.fetch("evaluation_llm_model") || ENV.fetch("EVALUATION_LLM_MODEL", "gpt-5.4")
    # Fallback models for evaluation chats (improver, extractor, suggester), comma-separated; blank disables.
    # A different provider than `evaluation` so a provider outage is survivable (RubyLLM Chat#with_fallbacks).
    def evaluation_fallbacks
      raw = Setting.fetch("evaluation_fallback_models") || ENV.fetch("EVALUATION_FALLBACK_MODELS", "mistral-large-latest")
      raw.to_s.split(",").map(&:strip).compact_blank
    end

    def judge         = Setting.fetch("judge_llm_model")      || ENV.fetch("JUDGE_LLM_MODEL",     "gpt-6-luna")
  end
end
