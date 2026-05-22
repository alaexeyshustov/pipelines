# frozen_string_literal: true

module Evaluation
  class ExperimentJob < ApplicationJob
    queue_as :default

    def perform(experiment)
      return if experiment.completed? || experiment.running?

      experiment.update!(status: :running)
      experiment.dataset.dataset_samples.each_with_index do |dataset_sample, index|
        RunEvalJob.set(wait: 3.seconds * index).perform_later(experiment.id, dataset_sample.id)
      end
    end
  end
end
