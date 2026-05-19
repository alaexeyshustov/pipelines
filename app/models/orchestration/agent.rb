# frozen_string_literal: true

module Orchestration
  class Agent < ApplicationRecord
    ALLOWED_TOOL_NAMESPACES = %w[Records Emails].freeze

    self.table_name = "orchestration_agents"

    has_many :actions, -> { where(kind: :agent) }, class_name: "Orchestration::Action", foreign_key: :agent_id, dependent: :restrict_with_error, inverse_of: :agent

    validates :name, presence: true, uniqueness: true
    validate :tools_must_be_valid

    scope :enabled, -> { where(enabled: true) }

    before_destroy :ensure_not_referenced

    def self.available_tools
      Dir.glob(Rails.root.join("app/tools/**/*.rb")).filter_map do |path|
        relative = path.delete_prefix("#{Rails.root}/app/tools/")
        class_name = relative.delete_suffix(".rb").split("/").map(&:camelize).join("::")
        namespace = class_name.split("::").first
        next unless ALLOWED_TOOL_NAMESPACES.include?(namespace)
        class_name if class_name.constantize < RubyLLM::Tool
      rescue NameError
        nil
      end.sort
    end

    def self.available_models
      RubyLLM.models.all
        .select { |m| m.type.to_s == "chat" }
        .group_by { |m| m.provider.to_s }
        .transform_values { |models| models.map(&:id).sort }
        .sort_by { |provider, _| provider }
    end

    private

    def tools_must_be_valid
      return if tools.blank?

      tools.each do |tool|
        namespace = tool.to_s.split("::").first
        unless ALLOWED_TOOL_NAMESPACES.include?(namespace)
          errors.add(:tools, "contains tool outside allowed namespaces: #{tool}")
          next
        end

        tool.constantize
      rescue NameError
        errors.add(:tools, "contains invalid tool: #{tool}")
      end
    end

    def ensure_not_referenced
      return unless Orchestration::Action.exists?(agent_id: id)

      errors.add(:base, "cannot be deleted while referenced by actions")
      throw :abort
    end
  end
end
