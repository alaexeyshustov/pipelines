module Orchestration
  class Pipeline < ApplicationRecord
    self.table_name = "pipelines"

    has_many :steps, -> { order(:position) }, class_name: "Orchestration::Step", dependent: :destroy
    has_many :pipeline_runs, class_name: "Orchestration::PipelineRun", dependent: :destroy

    validates :name, presence: true

    def next_run_at(from: Time.current)
      return nil if cron_expression.blank?
      cron = Fugit::Cron.parse(cron_expression)
      return nil unless cron
      cron.next_time(from).to_t
    end
  end
end
