module Orchestration
  class Step < ApplicationRecord
    self.table_name = "orchestration_steps"

    belongs_to :pipeline, class_name: "Orchestration::Pipeline", inverse_of: :steps
    has_many :step_actions, -> { order(:position) }, class_name: "Orchestration::StepAction", dependent: :destroy, inverse_of: :step
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
      statuses = action_runs.map(&:status)
      return "pending"   if statuses.empty?
      return "failed"    if statuses.include?("failed")
      return "running"   if statuses.include?("running")
      return "completed" if statuses.all?("completed")

      "pending"
    end
  end
end
