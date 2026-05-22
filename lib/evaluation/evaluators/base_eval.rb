# frozen_string_literal: true

module Evaluation
  module Evaluators
    class BaseEval
      def evaluate(sample, dataset_sample)
        raise NotImplementedError, "#{self.class}#evaluate must be implemented"
      end

      def evaluate_and_store(experiment, sample)
        @experiment = experiment
        @sample = sample
        dataset_sample = sample.dataset_sample
        result = evaluate(sample, dataset_sample)
        EvaluationResult.create!(
          experiment: experiment,
          dataset_sample: dataset_sample,
          sample: sample,
          score: result,
          evaluator_class: self.class.name
        )
      end
    end
  end
end
