# frozen_string_literal: true

module LlmModels
  class << self
    def emails_agent  = ENV.fetch("EMAILS_AGENT_MODEL", "mistral-large-latest")
    def records_agent = ENV.fetch("RECORDS_AGENT_MODEL", "gpt-5.1")
    def evaluation    = ENV.fetch("EVALUATION_LLM_MODEL", "gpt-5.4")
    def judge         = ENV.fetch("JUDGE_LLM_MODEL", "gpt-5.4")
  end
end
