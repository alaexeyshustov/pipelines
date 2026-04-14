module Orchestration
  class ActionRun < ApplicationRecord
    include Leva::Recordable

    self.table_name = "action_runs"

    STATUSES = %w[pending running completed failed].freeze

    belongs_to :pipeline_run, class_name: "Orchestration::PipelineRun"
    belongs_to :step_action, class_name: "Orchestration::StepAction"
    belongs_to :chat, optional: true

    validates :status, presence: true, inclusion: { in: STATUSES }

    def ground_truth
      output&.dig("classification")
    end

    def index_attributes
      {
        status: status,
        action: step_action.action.name,
        started_at: started_at,
        finished_at: finished_at
      }
    end

    def show_attributes
      {
        status: status,
        action: step_action.action.name,
        input: input,
        output: output,
        error: error,
        started_at: started_at,
        finished_at: finished_at
      }
    end

    def to_llm_context
      {
        action: step_action.action.name,
        input: input,
        status: status
      }
    end
  end
end
