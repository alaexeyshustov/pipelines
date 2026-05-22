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
      end
    end
  end
end
