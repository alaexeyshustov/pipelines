# frozen_string_literal: true

module Orchestration
  class Action < ApplicationRecord
    self.table_name = "orchestration_actions"

    enum :kind, { agent: "agent", service: "service" }, default: :service

    has_many :step_actions, class_name: "Orchestration::StepAction", dependent: :restrict_with_error
    belongs_to :agent, class_name: "Orchestration::Agent", optional: true

    validates :name, presence: true
    validate :kind_specific_fields_valid

    private

    def kind_specific_fields_valid
      if agent?
        errors.add(:agent_id, "must be present for agent-kind actions") if agent_id.blank?
        errors.add(:agent_class, "must be blank for agent-kind actions") if agent_class.present?
      else
        errors.add(:agent_id, "must be blank for service-kind actions") if agent_id.present?
        validate_service_class
      end
    end

    def validate_service_class
      if agent_class.blank?
        errors.add(:agent_class, "can't be blank")
        return
      end

      unless PipelineRunner::EXECUTORS.key?(agent_class)
        errors.add(:agent_class, "must be a registered executor")
      end
    end
  end
end
