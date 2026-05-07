# frozen_string_literal: true

module UI
  class SidebarComponent < ViewComponent::Base
    NavItem = Data.define(:label, :path)
    NavGroup = Data.define(:label, :items)

    def initialize(current_path:)
      @current_path = current_path
    end

    def nav_groups
      [
        NavGroup.new(
          label: "LLM",
          items: [
            NavItem.new(label: "Chats",      path: helpers.chats_path),
            NavItem.new(label: "Models",     path: helpers.models_path),
            NavItem.new(label: "Monitoring", path: helpers.ruby_llm_monitoring.root_path),
            NavItem.new(label: "Evaluation", path: helpers.leva.root_path)
          ]
        ),
        NavGroup.new(
          label: "Mails",
          items: [
            NavItem.new(label: "Application Emails", path: helpers.application_mails_path),
            NavItem.new(label: "Interviews",         path: helpers.interviews_path)
          ]
        ),
        NavGroup.new(
          label: "Orchestration",
          items: [
            NavItem.new(label: "Pipelines",     path: helpers.orchestration_pipelines_path),
            NavItem.new(label: "Actions",       path: helpers.orchestration_actions_path),
            NavItem.new(label: "Agents",        path: helpers.orchestration_agents_path),
            NavItem.new(label: "Pipeline Runs", path: helpers.orchestration_pipeline_runs_path)
          ]
        ),
        NavGroup.new(
          label: "Settings",
          items: [
            NavItem.new(label: "Email Connectors", path: helpers.settings_email_connectors_path)
          ]
        )
      ]
    end

    def group_open?(group)
      group.items.any? { |item| @current_path.start_with?(item.path) }
    end

    def active?(path)
      @current_path == path
    end
  end
end
