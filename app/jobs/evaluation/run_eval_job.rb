# frozen_string_literal: true

module Evaluation
  class RunEvalJob < ApplicationJob
    queue_as :default

    def perform(experiment_id, dataset_sample_id)
      experiment = Evaluation::Experiment.find(experiment_id)
      dataset_sample = Evaluation::DatasetSample.find(dataset_sample_id)
      run = experiment.runner_class.constantize.new
      evals = experiment.evaluator_classes.compact.reject(&:empty?).map(&:constantize).map(&:new)
      sample = run.execute_and_store(experiment, dataset_sample, experiment.prompt)
      evals.each { |e| e.evaluate_and_store(experiment, sample) }
      experiment.update!(status: :completed) if last?(experiment)
    end

    private

    def last?(experiment)
      experiment.dataset.dataset_samples.count == experiment.samples.count
    end
  end
end
