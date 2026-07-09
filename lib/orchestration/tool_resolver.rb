# frozen_string_literal: true

module Orchestration
  class ToolResolver
    def initialize(agent:)
      @agent = agent
    end

    def resolve
      configured = @agent.tools.presence
      return resolve_configured(configured) if configured

      agent_class = @agent.name.safe_constantize # : singleton(RubyLLM::Agent)
      return agent_class.tools if agent_class.respond_to?(:tools) # steep:ignore

      raise ArgumentError, "agent #{@agent.name.inspect} has no configured tools"
    end

    private

    def resolve_configured(configured)
      configured.map { |tool| resolve_class(tool) }
    end

    def resolve_class(tool)
      namespace = tool.to_s.split("::").first
      unless Orchestration::Agent::ALLOWED_TOOL_NAMESPACES.include?(namespace)
        raise ArgumentError, "Tool '#{tool}' is outside allowed namespaces"
      end

      tool.constantize
    rescue NameError
      raise ArgumentError, "Unknown tool class: #{tool}"
    end
  end
end
