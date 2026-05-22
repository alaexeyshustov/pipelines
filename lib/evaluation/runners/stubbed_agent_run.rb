# frozen_string_literal: true

module Evaluation
  module Runners
    # TODO: rename to param mapper
    class StubbedAgentRun < BaseRun
      def execute(dataset_sample)
        expected_tool_calls = (dataset_sample.expected_tool_calls || []).map(&:deep_symbolize_keys)
        registry = ToolStubRegistry.new(expected_tool_calls)

        agent_record = find_agent_record
        raise ArgumentError, "No agent found for experiment" unless agent_record

        action = find_action_for(agent_record)
        raise ArgumentError, "No action found for agent #{agent_record.name}" unless action

        tool_classes = resolve_tools(agent_record)
        stubbed_tools = tool_classes.map { |tool_class| stub_tool(tool_class, registry) }
        pipeline_model = @experiment&.sample_model
        policy = Orchestration::AgentResolutionPolicy.call(
          action: action,
          tool_classes: stubbed_tools,
          pipeline_model: pipeline_model,
          prompt_override: @prompt&.system_prompt
        )
        agent = Orchestration::RuntimeAgentBuilder.new(policy: policy).build

        result = agent.ask(dataset_sample.input.to_json)

        build_prediction(agent, result)
      end

      private

      def resolve_tools(agent_record)
        configured = agent_record.tools.presence
        return configured.map(&:constantize) if configured

        agent_class = agent_record.name.safe_constantize
        return agent_class.tools if agent_class.respond_to?(:tools)

        raise ArgumentError, "agent #{agent_record.name.inspect} has no configured tools"
      end

      def stub_tool(tool_class, registry)
        # steep:ignore:start
        Class.new(tool_class) do
          define_method(:execute) do |**kwargs|
            registry.lookup(tool_name: name, arguments: kwargs.transform_keys(&:to_s))
          end
        end
        # steep:ignore:end
      end

      def build_prediction(agent, result)
        # steep:ignore:start
        tool_calls = agent.messages
                          .where(role: "tool")
                          .order(:id)
                          .includes(:parent_tool_call)
                          .filter_map do |msg|
                            tc = msg.parent_tool_call
                            tc && { tool_name: tc.name, arguments: tc.arguments }
                          end
        # steep:ignore:end

        { tool_calls: tool_calls, output: result.content }.to_json
      end
    end
  end
end
