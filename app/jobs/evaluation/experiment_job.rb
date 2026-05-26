# frozen_string_literal: true

module Evaluation
  class ExperimentJob < ApplicationJob
    queue_as :default

    def perform(experiment)
      dataset_sample_ids = nil

      experiment.with_lock do
        if experiment.may_start_sampling?
          dataset_sample_ids = experiment.dataset.dataset_samples.ids
          experiment.update!(pending_samples_count: dataset_sample_ids.size)
          experiment.start_sampling!
        elsif experiment.sampling?
          dataset_sample_ids = recoverable_dataset_sample_ids(experiment)
        end
      end

      return if dataset_sample_ids.nil?

      if dataset_sample_ids.empty?
        experiment.with_lock { experiment.fail! if experiment.may_fail? }
        return
      end

      dataset_sample_ids.each { |dataset_sample_id| Evaluation::SamplingJob.perform_later(experiment.id, dataset_sample_id) }
    end

    private

    def recoverable_dataset_sample_ids(experiment)
      missing_dataset_sample_ids = experiment.dataset.dataset_samples
        .where.not(id: experiment.samples.select(:dataset_sample_id))
        .ids

      return nil if missing_dataset_sample_ids.empty?
      return nil if sampling_jobs_still_in_flight?(experiment.id)

      missing_dataset_sample_ids
    end

    def sampling_jobs_still_in_flight?(experiment_id)
      jobs = SolidQueue::Job
        .where(class_name: "Evaluation::SamplingJob", finished_at: nil)
        .where("arguments LIKE ?", "%[#{experiment_id},%")

      SolidQueue::ReadyExecution.where(job_id: jobs.select(:id)).exists? ||
        SolidQueue::ClaimedExecution.where(job_id: jobs.select(:id)).exists? ||
        SolidQueue::ScheduledExecution.where(job_id: jobs.select(:id)).exists? ||
        SolidQueue::BlockedExecution.where(job_id: jobs.select(:id)).exists?
    end
  end
end
