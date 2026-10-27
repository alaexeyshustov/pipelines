module Orchestration
  class AgentToolsComponent < ViewComponent::Base
    def initialize(available_tools:, selected:, errors: [])
      @available_tools = available_tools
      @selected        = Array(selected)
      @errors          = errors
    end

    def grouped_tools
      @available_tools.group_by { |t| t.split("::").first }
    end

    def selected?(tool)
      @selected.include?(tool)
    end
  end
end
