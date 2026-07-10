module Orchestration
  class PipelineRun < ApplicationRecord
    self.table_name = "orchestration_pipeline_runs"

    STATUSES = %w[pending running completed failed].freeze
    ACTIVE_STATUSES = %w[pending running].freeze
    TRIGGERED_BY = %w[manual schedule].freeze

    belongs_to :pipeline, class_name: "Orchestration::Pipeline"
    has_many :action_runs, class_name: "Orchestration::ActionRun", dependent: :destroy

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :triggered_by, inclusion: { in: TRIGGERED_BY }, allow_nil: true

    scope :recent_first, -> { order(created_at: :desc) }
    scope :in_progress, -> { where(status: ACTIVE_STATUSES) }
  end
end
