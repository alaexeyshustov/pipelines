# frozen_string_literal: true

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
module LlmModels
  class << self
    def emails_agent  = Setting.fetch("emails_agent_model")   || ENV.fetch("EMAILS_AGENT_MODEL",  "mistral-large-latest")
    def records_agent = Setting.fetch("records_agent_model")  || ENV.fetch("RECORDS_AGENT_MODEL", "gpt-5.1")
    def evaluation    = Setting.fetch("evaluation_llm_model") || ENV.fetch("EVALUATION_LLM_MODEL", "gpt-5.4")
    def judge         = Setting.fetch("judge_llm_model")      || ENV.fetch("JUDGE_LLM_MODEL",     "gpt-5.4")
  end
end
