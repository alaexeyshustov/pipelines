# frozen_string_literal: true

module Evaluation
  module Runners
    class StubbedAgentRun < BaseRun
      def execute(record)
        raise ArgumentError, "StubbedAgentRun requires an Orchestration::ActionRun, got #{record.class}" unless record.is_a?(Orchestration::ActionRun)

        expected_tool_calls = Evaluation::ToolCallExtractor.call(record.chat)
        registry = Evaluation::ToolStubRegistry.new(expected_tool_calls)

        action = record.step_action.action
        agent_record = action.agent
        raise ArgumentError, "action #{record.id} is not agent-kind or has no agent" unless agent_record

        tool_classes = resolve_tools(agent_record)
        stubbed_tools = tool_classes.map { |tool_class| stub_tool(tool_class, registry) }
        pipeline_model = @experiment&.sample_model
        agent = Orchestration::RuntimeAgentBuilder.new(
          action: action,
          tool_classes: stubbed_tools,
          pipeline_model: pipeline_model,
          prompt_override: @prompt&.system_prompt
        ).build

        result = agent.ask(record.input.to_json)

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
