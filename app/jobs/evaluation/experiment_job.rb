
module Evaluation
  class ExperimentJob < ApplicationJob
    queue_as :default

    def perform(experiment)
      dataset_sample_ids = determine_sample_ids(experiment)
      return if dataset_sample_ids.nil?

      if dataset_sample_ids.empty?
        experiment.with_lock { experiment.fail! if experiment.may_fail? }
        return
      end

      dataset_sample_ids.each { |id| Evaluation::SamplingJob.perform_later(experiment.id, id) }
    end

    private

    def determine_sample_ids(experiment)
      experiment.with_lock { sampling_ids_from_state(experiment) }
    end

    def sampling_ids_from_state(experiment)
      if experiment.may_start_sampling?
        ids = experiment.dataset.dataset_samples.ids
        experiment.update!(pending_samples_count: ids.size)
        experiment.start_sampling!
        ids
      elsif experiment.sampling?
        recoverable_dataset_sample_ids(experiment)
      end
    end

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

      SolidQueue::ReadyExecution.exists?(job_id: jobs.select(:id)) ||
        SolidQueue::ClaimedExecution.exists?(job_id: jobs.select(:id)) ||
        SolidQueue::ScheduledExecution.exists?(job_id: jobs.select(:id)) ||
        SolidQueue::BlockedExecution.exists?(job_id: jobs.select(:id))
    end
  end
end
