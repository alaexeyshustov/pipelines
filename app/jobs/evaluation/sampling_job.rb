# frozen_string_literal: true

module Evaluation
  class SamplingJob < ApplicationJob
    queue_as :default

    retry_on RubyLLM::Error, attempts: 3 do |job, _error|
      experiment = Evaluation::Experiment.find_by(id: job.arguments[0])
      next unless experiment

      job.decrement_and_transition(experiment)
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

    def decrement_and_transition(experiment)
      sample_ids = []

      experiment.with_lock do
        break if experiment.pending_samples_count <= 0

        experiment.decrement!(:pending_samples_count)
        sample_ids = evaluate_threshold(experiment) if experiment.pending_samples_count.zero?
      end

      sample_ids.each { |sid| EvaluationJob.perform_later(experiment.id, sid) }
    end

    private

    def evaluate_threshold(experiment)
      total = experiment.dataset.dataset_samples.count
      sample_ids = experiment.samples.ids

      if sample_ids.size * 10 >= total * 8
        experiment.update!(pending_evaluations_count: sample_ids.size)
        experiment.start_evaluating!
        sample_ids
      else
        experiment.fail!
        []
      end
    end
  end
end
