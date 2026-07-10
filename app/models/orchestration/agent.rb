# frozen_string_literal: true

module Orchestration
  class Agent < ApplicationRecord
    ALLOWED_TOOL_NAMESPACES = %w[Records Emails].freeze

    self.table_name = "orchestration_agents"

    has_many :actions, -> { where(kind: :agent) }, class_name: "Orchestration::Action", foreign_key: :agent_id, dependent: :restrict_with_error, inverse_of: :agent

    validates :name, presence: true, uniqueness: true
    validate :tools_must_be_valid

    scope :enabled, -> { where(enabled: true) }
    scope :with_action_counts, -> {
      left_joins(:actions)
        .select("orchestration_agents.*, COUNT(DISTINCT orchestration_actions.id) AS action_count")
        .group("orchestration_agents.id")
        .order("orchestration_agents.name")
    }

    before_destroy :ensure_not_referenced

    def actions_with_usage
      actions.includes(step_actions: { step: :pipeline }).order(:name)
    end

    def self.named(name) = find_by(name:)

    def self.available_tools
      Rails.root.glob("app/tools/**/*.rb")
        .filter_map { |path| tool_class_name_from_path(path) }
        .sort
    end

    def self.tool_class_name_from_path(path)
      relative = path.relative_path_from(Rails.root.join("app/tools")).to_s
      class_name = relative.delete_suffix(".rb").split("/").map(&:camelize).join("::")
      namespace = class_name.split("::").first
      return unless ALLOWED_TOOL_NAMESPACES.include?(namespace)

      class_name if class_name.constantize < RubyLLM::Tool
    rescue NameError
      nil
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

      tools.each { |tool| validate_tool(tool) }
    end

    def validate_tool(tool)
      namespace = tool.to_s.split("::").first
      unless ALLOWED_TOOL_NAMESPACES.include?(namespace)
        errors.add(:tools, "contains tool outside allowed namespaces: #{tool}")
        return
      end

      tool.constantize
    rescue NameError
      errors.add(:tools, "contains invalid tool: #{tool}")
    end

    def ensure_not_referenced
      return unless Orchestration::Action.exists?(agent_id: id)

      errors.add(:base, "cannot be deleted while referenced by actions")
      throw :abort
    end
  end
end
