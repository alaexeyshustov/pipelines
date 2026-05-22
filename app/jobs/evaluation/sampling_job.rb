# frozen_string_literal: true

module Evaluation
  class SamplingJob < ApplicationJob
    queue_as :default

    retry_on StandardError, attempts: 3 do |job, _error|
      experiment = Evaluation::Experiment.find_by(id: job.arguments[0])
      next unless experiment

      job.send(:decrement_and_transition, experiment)
    end

    def perform(experiment_id, dataset_sample_id)
      experiment = Evaluation::Experiment.find(experiment_id)
      dataset_sample = Evaluation::DatasetSample.find(dataset_sample_id)

      Evaluation::Sampler.call(
        experiment: experiment,
        dataset_sample: dataset_sample,
        prompt: experiment.prompt
      )

      decrement_and_transition(experiment)
    end

    private

    def decrement_and_transition(experiment)
      sample_ids = nil

      experiment.with_lock do
        experiment.decrement!(:pending_samples_count)
        sample_ids = evaluate_threshold(experiment) if experiment.pending_samples_count.zero?
      end

      sample_ids&.each { |sid| EvaluationJob.perform_later(experiment.id, sid) }
    end

    def evaluate_threshold(experiment)
      total = experiment.dataset.dataset_samples.count
      completed_count = experiment.samples.count

      if completed_count >= total * 0.8
        sample_ids = experiment.samples.ids
        experiment.update!(pending_evaluations_count: sample_ids.size)
        experiment.start_evaluating!
        sample_ids
      else
        experiment.fail!
        nil
      end
    end
  end
end
