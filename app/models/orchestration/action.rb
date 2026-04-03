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
      return errors.add(:agent_class, "must be an existing constant") if klass.nil?

      is_agent      = klass.ancestors.include?(RubyLLM::Agent)
      is_executable = klass.ancestors.include?(Orchestration::Executable)

      unless is_agent || is_executable
        errors.add(:agent_class, "must inherit from RubyLLM::Agent or include Orchestration::Executable")
      end
    end
  end
end
