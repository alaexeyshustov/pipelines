module Orchestration
  class StepAction < ApplicationRecord
    self.table_name = "step_actions"

    belongs_to :step, class_name: "Orchestration::Step"
    belongs_to :action, class_name: "Orchestration::Action"

    validates :position, presence: true, uniqueness: { scope: :step_id }
  end
end
