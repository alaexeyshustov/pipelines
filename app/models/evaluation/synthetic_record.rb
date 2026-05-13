# frozen_string_literal: true

module Evaluation
  # Lightweight value objects to satisfy LLMJudgeEval's duck-type contract.
  SyntheticAction = Data.define(:agent_class) do
    def agent? = false
    def agent  = nil
  end

  SyntheticStepAction = Data.define(:action)

  class SyntheticRecord < ApplicationRecord
    self.table_name = "evaluation_synthetic_records"

    validates :agent_name, presence: true
    validates :input,      presence: true

    # Returns a step_action value object so LLMJudgeEval#agent_name works.
    def step_action
      SyntheticStepAction.new(action: SyntheticAction.new(agent_class: agent_name))
    end

    # No real chat — ToolCallExtractor handles nil gracefully.
    def chat = nil
  end
end
