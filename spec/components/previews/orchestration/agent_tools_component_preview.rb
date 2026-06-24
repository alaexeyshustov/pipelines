# frozen_string_literal: true

module Orchestration
  class AgentToolsComponentPreview < ViewComponent::Preview
    TOOLS = %w[
      Records::InsertRowsTool
      Records::TempFileTool
      Emails::FetchTool
    ].freeze

    def default
      render(Orchestration::AgentToolsComponent.new(
        available_tools: TOOLS,
        selected: %w[Records::InsertRowsTool]
      ))
    end

    def all_selected
      render(Orchestration::AgentToolsComponent.new(
        available_tools: TOOLS,
        selected: TOOLS
      ))
    end

    def with_errors
      render(Orchestration::AgentToolsComponent.new(
        available_tools: TOOLS,
        selected: [],
        errors: [ "At least one tool must be selected" ]
      ))
    end
  end
end
