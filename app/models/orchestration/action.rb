module Orchestration
  class Action < ApplicationRecord
    self.table_name = "actions"

    has_many :step_actions, class_name: "Orchestration::StepAction", dependent: :restrict_with_error

    validates :name, presence: true
    validates :agent_class, presence: true
    validate :agent_class_must_be_valid

    private

    def agent_class_must_be_valid
      return if agent_class.blank?

      klass = agent_class.safe_constantize
      if klass.nil?
        errors.add(:agent_class, "must be an existing constant")
      elsif !klass.ancestors.include?(RubyLLM::Agent)
        errors.add(:agent_class, "must inherit from RubyLLM::Agent")
      end
    end
  end
end
