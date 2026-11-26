module Orchestration
  class PipelineRun < ApplicationRecord
    self.table_name = "orchestration_pipeline_runs"

    STATUSES = %w[pending running completed failed].freeze
    ACTIVE_STATUSES = %w[pending running].freeze
    TERMINAL_STATUSES = %w[completed failed].freeze
    TRIGGERED_BY = %w[manual schedule].freeze
    # An in-progress run that has not shown a sign of life (heartbeat_at, else started_at, else created_at) for this
    # long is taken for dead (its job was lost, e.g. on a deploy) and stops blocking new runs.
    STALE_AFTER = 10.minutes

    belongs_to :pipeline, class_name: "Orchestration::Pipeline"
    has_many :action_runs, class_name: "Orchestration::ActionRun", dependent: :destroy

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :triggered_by, inclusion: { in: TRIGGERED_BY }, allow_nil: true

    scope :recent_first, -> { order(created_at: :desc) }
    scope :in_progress, -> { where(status: ACTIVE_STATUSES) }
    scope :blocking, -> { in_progress.where("COALESCE(heartbeat_at, started_at, created_at) >= ?", STALE_AFTER.ago) }
  end
end
