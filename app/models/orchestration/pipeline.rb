module Orchestration
  class Pipeline < ApplicationRecord
    self.table_name = "orchestration_pipelines"

    has_many :steps, -> { order(:position) }, class_name: "Orchestration::Step", dependent: :destroy, inverse_of: :pipeline
    has_many :pipeline_runs, class_name: "Orchestration::PipelineRun", dependent: :destroy

    validates :name, presence: true
    validate :cron_expression_parseable, if: -> { cron_expression.present? }

    scope :with_step_counts, -> {
      left_joins(:steps)
        .select("orchestration_pipelines.*, COUNT(orchestration_steps.id) AS step_count")
        .group("orchestration_pipelines.id")
        .order("orchestration_pipelines.name")
    }

    def validate_steps
      PipelineValidator.new(self).validate
    end

    def latest_run
      pipeline_runs.recent_first.first
    end

    def run_in_progress?
      pipeline_runs.in_progress.exists?
    end

    def enabled_steps
      steps.where(enabled: true)
    end

    def steps_with_actions
      steps.includes(step_actions: { action: :agent })
    end

    def next_run_at(from: Time.current)
      return nil if cron_expression.blank?
      cron = Fugit::Cron.parse(cron_expression)
      return nil unless cron
      cron.next_time(from).to_t
    end

    private

    def cron_expression_parseable
      errors.add(:cron_expression, "is not a valid cron expression") unless Fugit::Cron.parse(cron_expression)
    end
  end
end
