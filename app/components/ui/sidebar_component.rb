
module UI
  class SidebarComponent < ViewComponent::Base
    NavItem = Data.define(:label, :path)
    NavGroup = Data.define(:label, :items)

    def initialize(current_path:)
      @current_path = current_path
    end

    def nav_groups
      [ llm_nav_group, mails_nav_group, orchestration_nav_group, settings_nav_group ]
    end

    def root_path
      helpers.main_app.root_path
    end

    def group_open?(group)
      group.items.any? { |item| current_path_matches?(item.path) }
    end

    def active?(path)
      current_path_matches?(path)
    end

    private

    def llm_nav_group
      ma = helpers.main_app
      NavGroup.new(label: "LLM", items: [
        NavItem.new(label: "Chats",      path: ma.chats_path),
        NavItem.new(label: "Models",     path: ma.models_path),
        NavItem.new(label: "Monitoring", path: "/monitoring"),
        NavItem.new(label: "Evaluation", path: "/evaluation"),
        NavItem.new(label: "Prompts",    path: "/evaluation/prompts")
      ])
    end

    def mails_nav_group
      ma = helpers.main_app
      NavGroup.new(label: "Mails", items: [
        NavItem.new(label: "Application Emails", path: ma.application_mails_path),
        NavItem.new(label: "Interviews",         path: ma.interviews_path)
      ])
    end

    def orchestration_nav_group
      ma = helpers.main_app
      NavGroup.new(label: "Orchestration", items: [
        NavItem.new(label: "Pipelines",     path: ma.orchestration_pipelines_path),
        NavItem.new(label: "Actions",       path: ma.orchestration_actions_path),
        NavItem.new(label: "Agents",        path: ma.orchestration_agents_path),
        NavItem.new(label: "Pipeline Runs", path: ma.orchestration_pipeline_runs_path)
      ])
    end

    def settings_nav_group
      ma = helpers.main_app
      NavGroup.new(label: "Settings", items: [
        NavItem.new(label: "Email Connectors", path: ma.settings_email_connectors_path),
        NavItem.new(label: "Jobs",             path: "/jobs")
      ])
    end

    def current_path_matches?(path)
      @current_path == path || @current_path.start_with?("#{path}/")
    end
  end
end
