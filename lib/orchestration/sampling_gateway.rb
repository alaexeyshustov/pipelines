# frozen_string_literal: true

module Orchestration
  class AgentNotFound < ArgumentError; end
  class ActionNotFound < ArgumentError; end

  module SamplingGateway
    def self.build(agent_name:, pipeline_model:, prompt_override: nil, tool_transform: nil)
      validate_tool_transform!(tool_transform)

      agent_record = find_agent!(agent_name)
      action_record = find_action!(agent_record, agent_name)

      tools = Orchestration::ToolResolver.new(agent: agent_record).resolve
      tools = tool_transform.call(tools) if tool_transform

      policy = Orchestration::AgentResolutionPolicy.new(
        action: action_record,
        tool_classes: tools,
        pipeline_model: pipeline_model,
        prompt_override: prompt_override
      ).resolve
      Orchestration::RuntimeAgentBuilder.new(policy:).build
    end

    def self.validate_tool_transform!(tool_transform)
      return unless tool_transform && !tool_transform.respond_to?(:call)

      raise ArgumentError, "tool_transform must respond to #call"
    end
    private_class_method :validate_tool_transform!

    def self.find_agent!(agent_name)
      raise AgentNotFound, "No agent found for #{agent_name}" if agent_name.nil?

      Orchestration::Agent.named(agent_name) or raise AgentNotFound, "No agent found for #{agent_name}"
    end
    private_class_method :find_agent!

    def self.find_action!(agent_record, agent_name)
      Orchestration::Action.where(kind: :agent, agent_id: agent_record.id).first or
        raise ActionNotFound, "No action found for agent #{agent_name}"
    end
    private_class_method :find_action!
  end
end
