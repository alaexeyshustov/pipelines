module Orchestration
  class Step < ApplicationRecord
    self.table_name = "steps"

    belongs_to :pipeline, class_name: "Orchestration::Pipeline"
    has_many :step_actions, -> { order(:position) }, class_name: "Orchestration::StepAction", dependent: :destroy
    has_many :actions, through: :step_actions, class_name: "Orchestration::Action"

    validates :name, presence: true
    validates :position, presence: true, uniqueness: { scope: :pipeline_id }
  end
end
