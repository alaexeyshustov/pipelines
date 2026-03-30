module Orchestration
  class Pipeline < ApplicationRecord
    self.table_name = "pipelines"

    has_many :steps, -> { order(:position) }, class_name: "Orchestration::Step", dependent: :destroy
    has_many :pipeline_runs, class_name: "Orchestration::PipelineRun", dependent: :destroy

    validates :name, presence: true
    validate :cron_expression_parseable, if: -> { cron_expression.present? }

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
