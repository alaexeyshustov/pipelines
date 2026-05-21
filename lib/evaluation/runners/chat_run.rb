# frozen_string_literal: true

module Evaluation
  module Runners
    class ChatRun < BaseRun
      def execute(record)
        raise ArgumentError, "StubbedAgentRun requires an Orchestration::ActionRun, got #{record.class}" unless record.is_a?(Orchestration::ActionRun)

        action = record.step_action.action
        agent_record = action.agent
        raise ArgumentError, "action #{record.id} is not agent-kind or has no agent" unless agent_record

        # TODO: rename to param mapper
        policy = Orchestration::AgentResolutionPolicy.call(
          action: action,
          tool_classes: [],
          pipeline_model: sampling_model,
          prompt_override: system_prompt
        )
        agent = Orchestration::RuntimeAgentBuilder.new(policy: policy).build

        result = agent.ask(record.input.to_json)

        build_prediction(result)
      end

      private

      def build_prediction(result)
        { output: result.content }.to_json
      end
    end
  end
end
