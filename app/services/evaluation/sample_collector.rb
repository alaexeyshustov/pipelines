module Evaluation
  class SampleCollector
    Sample = Data.define(:action_run_id, :input, :expected_tool_calls)

    def self.call(agent_name:, sample_size:)
      new(agent_name: agent_name, sample_size: sample_size).call
    end

    def initialize(agent_name:, sample_size:)
      @agent_name = agent_name
      @sample_size = sample_size
    end

    def call
      action_runs.map do |action_run|
        Sample.new(
          action_run_id: action_run.id,
          input: action_run.input,
          expected_tool_calls: extract_tool_calls(action_run.chat)
        )
      end
    end

    private

    def action_runs
      # steep:ignore:start
      Orchestration::ActionRun
        .joins(step_action: :action)
        .includes(chat: { messages: :parent_tool_call })
        .where(status: "completed")
        .where.not(chat_id: nil)
        .where(actions: { agent_class: @agent_name })
        .order(id: :desc)
        .limit(@sample_size)
      # steep:ignore:end
    end

    def extract_tool_calls(chat)
      ToolCallExtractor.call(chat)
    end
  end
end
