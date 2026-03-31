module Orchestration
  class Step < ApplicationRecord
    self.table_name = "steps"

    belongs_to :pipeline, class_name: "Orchestration::Pipeline"
    has_many :step_actions, -> { order(:position) }, class_name: "Orchestration::StepAction", dependent: :destroy
    has_many :actions, through: :step_actions, class_name: "Orchestration::Action"

    validates :name, presence: true
    validates :position, presence: true, uniqueness: { scope: :pipeline_id }

    def swap_position_with(other)
      pos_a = position
      pos_b = other.position
      temp  = pipeline.steps.maximum(:position) + 1

      ActiveRecord::Base.transaction do
        update_column(:position, temp)
        other.update_column(:position, pos_a)
        update_column(:position, pos_b)
      end
    end

    def self.derive_status(action_runs)
      return "pending" if action_runs.empty?
      return "failed" if action_runs.any? { |ar| ar.status == "failed" }
      return "running" if action_runs.any? { |ar| ar.status == "running" }
      return "completed" if action_runs.all? { |ar| ar.status == "completed" }

      "pending"
    end
  end
end
