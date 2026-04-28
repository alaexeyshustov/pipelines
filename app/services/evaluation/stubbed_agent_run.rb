module Evaluation
  class StubbedAgentRun < Leva::BaseRun
    def execute(record)
      expected_tool_calls = extract_tool_calls_from(record.chat)
      registry = Evaluation::ToolStubRegistry.new(expected_tool_calls)

      # steep:ignore:start
      agent_class_name = record.step_action.action.agent_class
      raise ArgumentError, "agent_class is nil for action_run #{record.id}" unless agent_class_name

      agent_class = agent_class_name.constantize
      stubbed_tools = agent_class.tools.map { |tool_class| stub_tool(tool_class, registry) }

      agent = agent_class.create
      agent.with_tools(*stubbed_tools, replace: true)

      result = agent.ask(record.input.to_json)
      # steep:ignore:end

      build_prediction(agent, result)
    end

    private

    def extract_tool_calls_from(chat)
      return [] if chat.nil?

      # steep:ignore:start
      chat.messages
          .includes(:parent_tool_call)
          .where(role: "tool")
          .order(:id)
          .filter_map do |msg|
            tc = msg.parent_tool_call
            tc && { tool_name: tc.name, arguments: tc.arguments, result: msg.content }
          end
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

      output = result.content.is_a?(String) ? result.content : result.content.to_json
      { tool_calls: tool_calls, output: output }.to_json
    end
  end
end
