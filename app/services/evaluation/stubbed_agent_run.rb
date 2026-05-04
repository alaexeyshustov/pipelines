module Evaluation
  class StubbedAgentRun < Leva::BaseRun
    def execute(record)
      expected_tool_calls = ToolCallExtractor.call(record.chat)
      registry = Evaluation::ToolStubRegistry.new(expected_tool_calls)

      # steep:ignore:start
      action = record.step_action.action
      agent_record = action.agent
      raise ArgumentError, "action #{record.id} is not agent-kind or has no agent" unless agent_record

      agent_class_name = agent_record.name
      agent_class = agent_class_name.safe_constantize
      raise ArgumentError, "agent class #{agent_class_name.inspect} could not be resolved for action_run #{record.id}" unless agent_class

      tool_classes = resolve_tools(agent_record, agent_class)
      stubbed_tools = tool_classes.map { |tool_class| stub_tool(tool_class, registry) }

      agent = agent_class.create
      agent = agent.with_tools(*stubbed_tools, replace: true)

      result = agent.ask(record.input.to_json)
      # steep:ignore:end

      build_prediction(agent, result)
    end

    private

    def resolve_tools(agent_record, agent_class)
      # steep:ignore:start
      configured = agent_record.tools.presence
      return configured.map(&:constantize) if configured

      agent_class.tools
      # steep:ignore:end
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
