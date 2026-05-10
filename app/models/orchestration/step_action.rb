module Orchestration
  class StepAction < ApplicationRecord
    self.table_name = "step_actions"

    OUTPUT_KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

    belongs_to :step, class_name: "Orchestration::Step"
    belongs_to :action, class_name: "Orchestration::Action"
    has_many :action_runs, class_name: "Orchestration::ActionRun", dependent: :restrict_with_error

    validates :position, presence: true, uniqueness: { scope: :step_id }
    validates :output_key,
              presence: true,
              format: { with: OUTPUT_KEY_FORMAT },
              uniqueness: { scope: :step_id }
    validate :output_key_immutable_after_first_run

    private

    def output_key_immutable_after_first_run
      return unless persisted? && output_key_changed?
      return unless action_runs.exists?

      errors.add(:output_key, "cannot be changed once a run exists for this step_action")
    end
  end
end
