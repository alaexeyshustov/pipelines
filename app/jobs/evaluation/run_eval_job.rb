# frozen_string_literal: true

module Evaluation
  class RunEvalJob < ApplicationJob
    queue_as :default

    ALLOWED_EVALUATORS = %w[Evaluation::Evaluators::LLMJudgeEval].freeze

    def perform(experiment_id, dataset_sample_id)
      experiment = Evaluation::Experiment.find(experiment_id)
      dataset_sample = Evaluation::DatasetSample.find(dataset_sample_id)
      evals = evaluators_for(experiment)
      sample = Evaluation::Sampler.call(experiment: experiment, dataset_sample: dataset_sample, prompt: experiment.prompt)
      evals.each { |e| e.evaluate_and_store(experiment, sample) }
      experiment.update!(status: :completed) if last?(experiment)
    end

    private

    def evaluators_for(experiment)
      experiment.evaluator_classes.compact.reject(&:empty?).map do |klass|
        raise ArgumentError, "Unrecognised evaluator class: #{klass}" unless ALLOWED_EVALUATORS.include?(klass)

        klass.constantize.new
      end
    end

    def last?(experiment)
      experiment.dataset.dataset_samples.count == experiment.samples.count
    end
  end
end
