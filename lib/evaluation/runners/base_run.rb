# frozen_string_literal: true

module Evaluation
  module Runners
    class BaseRun
      def execute(dataset_sample)
        raise NotImplementedError, "#{self.class}#execute must be implemented"
      end

      def execute_and_store(experiment, dataset_sample, prompt)
        @experiment = experiment
        @prompt = prompt
        result = JSON.parse(execute(dataset_sample))
        Sample.create!(
          experiment: experiment,
          dataset_sample: dataset_sample,
          prompt: prompt,
          tool_calls: result.fetch("tool_calls", []),
          output: result.fetch("output", "")
        )
      rescue JSON::ParserError => e
        Rails.logger.error("#{self.class}#execute_and_store: invalid JSON from execute: #{e.message}")
        raise
      end

      protected

      def find_agent_record
        agent_name = @experiment&.agent_name
        return unless agent_name

        Orchestration::Agent.find_by(name: agent_name)
      end

      def find_action_for(agent_record)
        Orchestration::Action.where(kind: :agent, agent_id: agent_record.id).first
      end
    end
  end
end
