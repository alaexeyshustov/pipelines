# frozen_string_literal: true

module Evaluation
  class ExperimentJob < ApplicationJob
    queue_as :default

    def perform(experiment)
      return unless experiment.may_start_sampling?

      experiment.start_sampling!
      total = experiment.dataset.dataset_samples.count
      experiment.update!(pending_samples_count: total)
      experiment.dataset.dataset_samples.each do |dataset_sample|
        SamplingJob.perform_later(experiment.id, dataset_sample.id)
      end
    end
  end
end
