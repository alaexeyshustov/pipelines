module Orchestration
  class PipelineRun < ApplicationRecord
    self.table_name = "pipeline_runs"

    STATUSES = %w[pending running completed failed].freeze
    TRIGGERED_BY = %w[manual schedule].freeze

    belongs_to :pipeline, class_name: "Orchestration::Pipeline"
    has_many :action_runs, class_name: "Orchestration::ActionRun", dependent: :destroy

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :triggered_by, inclusion: { in: TRIGGERED_BY }, allow_nil: true
  end
end
