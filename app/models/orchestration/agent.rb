# frozen_string_literal: true

module Orchestration
  class Agent < ApplicationRecord
    self.table_name = "orchestration_agents"

    validates :name, presence: true, uniqueness: true
    validate :tools_must_be_valid

    scope :enabled, -> { where(enabled: true) }

    before_destroy :ensure_not_referenced

    private

    def tools_must_be_valid
      return if tools.blank?

      tools.each do |tool|
        tool.constantize
      rescue NameError
        errors.add(:tools, "contains invalid tool: #{tool}")
      end
    end

    def ensure_not_referenced
      return unless Orchestration::Action.exists?(agent_class: name)

      errors.add(:base, "cannot be deleted while referenced by actions")
      throw :abort
    end
  end
end
