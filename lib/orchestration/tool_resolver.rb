# frozen_string_literal: true

module Orchestration
  class ToolResolver
    REGISTRY = {
      "Emails::AddLabelsTool"      => Emails::AddLabelsTool,
      "Emails::ClassifyTool"       => Emails::ClassifyTool,
      "Emails::CreateLabelTool"    => Emails::CreateLabelTool,
      "Emails::GetLabelsTool"      => Emails::GetLabelsTool,
      "Emails::GetTool"            => Emails::GetTool,
      "Emails::ListTool"           => Emails::ListTool,
      "Emails::SearchTool"         => Emails::SearchTool,
      "Records::InsertRowsTool"    => Records::InsertRowsTool,
      "Records::ListRowsTool"      => Records::ListRowsTool,
      "Records::ReadRowsTool"      => Records::ReadRowsTool,
      "Records::ReadSchemaTool"    => Records::ReadSchemaTool,
      "Records::SearchSimilarTool" => Records::SearchSimilarTool,
      "Records::TempFileTool"      => Records::TempFileTool,
      "Records::UpdateRowsTool"    => Records::UpdateRowsTool
    }.freeze

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
      REGISTRY.fetch(tool) { raise ArgumentError, "Unknown tool class: #{tool}" }
    end
  end
end
