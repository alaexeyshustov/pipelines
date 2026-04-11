module Orchestration
  class ActionRun < ApplicationRecord
    self.table_name = "action_runs"

    STATUSES = %w[pending running completed failed].freeze

    belongs_to :pipeline_run, class_name: "Orchestration::PipelineRun"
    belongs_to :step_action, class_name: "Orchestration::StepAction"
    belongs_to :chat, optional: true

    validates :status, presence: true, inclusion: { in: STATUSES }
  end
end
