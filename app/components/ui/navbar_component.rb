# frozen_string_literal: true

module UI
  class NavbarComponent < ViewComponent::Base
    NavItem = Data.define(:label, :path)

    def initialize(current_path:)
      @current_path = current_path
    end

    def nav_items
      [
        NavItem.new(label: "Chats",     path: helpers.chats_path),
        NavItem.new(label: "Pipelines", path: helpers.orchestration_pipelines_path),
        NavItem.new(label: "Actions",   path: helpers.orchestration_actions_path),
        NavItem.new(label: "Emails",    path: helpers.application_mails_path),
        NavItem.new(label: "Interviews", path: helpers.interviews_path),
        NavItem.new(label: "Monitoring", path: "/monitoring")
      ]
    end

    def active?(path)
      @current_path == path
    end
  end
end
