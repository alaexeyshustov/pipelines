# frozen_string_literal: true

module Orchestration
  class AgentNotFound < ArgumentError; end
  class ActionNotFound < ArgumentError; end

  module SamplingGateway
    def self.build(agent_name:, pipeline_model:, prompt_override: nil, tool_transform: nil)
      raise AgentNotFound, "No agent found for #{agent_name}" if agent_name.nil?

      agent_record = Orchestration::Agent.named(agent_name) or
        raise AgentNotFound, "No agent found for #{agent_name}"
      action_record = Orchestration::Action.where(kind: :agent, agent_id: agent_record.id).first or
        raise ActionNotFound, "No action found for agent #{agent_name}"

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
  end
end
