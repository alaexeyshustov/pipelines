# frozen_string_literal: true

# Central registry for LLM model names. All values are read from ENV at boot
# time and frozen for the lifetime of the process — a restart is required to
# pick up any ENV changes.
#
# ENV var naming note: EVALUATION_LLM_MODEL and JUDGE_LLM_MODEL pre-date this
# module and are preserved for backwards compatibility; new vars follow the
# <SUBJECT>_AGENT_MODEL convention.
module LlmModels
  class << self
    def emails_agent  = ENV.fetch("EMAILS_AGENT_MODEL", "mistral-large-latest")
    def records_agent = ENV.fetch("RECORDS_AGENT_MODEL", "gpt-5.1")
    def evaluation    = ENV.fetch("EVALUATION_LLM_MODEL", "gpt-5.4")
    def judge         = ENV.fetch("JUDGE_LLM_MODEL", "gpt-5.4")
  end
end
