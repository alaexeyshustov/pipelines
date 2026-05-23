# frozen_string_literal: true

module Evaluation
  class ExperimentJob < ApplicationJob
    queue_as :default

    def perform(experiment)
      total = nil

      experiment.with_lock do
        if experiment.may_start_sampling?
          total = experiment.dataset.dataset_samples.count
          experiment.update!(pending_samples_count: total)
          experiment.start_sampling!
        elsif experiment.sampling? &&
              experiment.pending_samples_count == experiment.dataset.dataset_samples.count
          # crash recovery: start_sampling! succeeded but enqueuing didn't complete
          total = experiment.pending_samples_count
        end
      end

      return if total.nil?

      if total.zero?
        experiment.with_lock { experiment.fail! if experiment.may_fail? }
        return
      end

      experiment.dataset.dataset_samples.each do |dataset_sample|
        SamplingJob.perform_later(experiment.id, dataset_sample.id)
      end
    end
  end
end
