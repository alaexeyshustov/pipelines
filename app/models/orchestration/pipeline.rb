module Orchestration
  class Pipeline < ApplicationRecord
    self.table_name = "pipelines"

    has_many :steps, -> { order(:position) }, class_name: "Orchestration::Step", dependent: :destroy
    has_many :pipeline_runs, class_name: "Orchestration::PipelineRun", dependent: :destroy

    validates :name, presence: true
  end
end
