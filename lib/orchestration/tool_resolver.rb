module Orchestration
  class ToolResolver
    REGISTRY = {
      "Emails::AddLabelsTool"      => Emails::AddLabelsTool,
      "Emails::ClassifyTool"       => Emails::ClassifyTool.with_classifier(Agents::EmailsClassifier),
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

    def self.lookup(name)
      REGISTRY.fetch(name) { raise ArgumentError, "Unknown tool class: #{name}" }
    end

    def initialize(agent:)
      @agent = agent
    end

    def resolve
      configured = @agent.tools.presence
      return resolve_configured(configured) if configured

      agent_class = @agent.name.safe_constantize
      return agent_class.tools if agent_class.is_a?(Class) && agent_class < RubyLLM::Agent

      raise ArgumentError, "agent #{@agent.name.inspect} has no configured tools"
    end

    private

    def resolve_configured(configured)
      configured.map { |tool| self.class.lookup(tool) }
    end
  end
end
