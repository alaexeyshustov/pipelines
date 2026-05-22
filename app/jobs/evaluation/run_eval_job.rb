# frozen_string_literal: true

module Evaluation
  class RunEvalJob < ApplicationJob
    queue_as :default

    def perform(experiment_id, dataset_sample_id)
      experiment = Evaluation::Experiment.find(experiment_id)
      dataset_sample = Evaluation::DatasetSample.find(dataset_sample_id)
      evals = experiment.evaluator_classes.compact.reject(&:empty?).map(&:constantize).map(&:new)
      sample = Evaluation::Sampler.call(experiment: experiment, dataset_sample: dataset_sample, prompt: experiment.prompt)
      evals.each { |e| e.evaluate_and_store(experiment, sample) }
      experiment.update!(status: :completed) if last?(experiment)
    end

    private

    def last?(experiment)
      experiment.dataset.dataset_samples.count == experiment.samples.count
    end
  end
end
