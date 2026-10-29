module Evaluation
  # Runs one dataset sample of an experiment end to end: the agent under test (Sampler), then the
  # judge (Grader) and persistence of the grades, all inside UsageScope so LLM usage is attributed
  # to the experiment.
  #
  # Retries: RubyLLM already retries HTTP-level failures (and falls back across models), so a
  # RubyLLM::Error reaching this job is final and the sample is counted as failed. Only raw
  # transport errors that RubyLLM does not wrap get one outer retry. Either way the job always
  # releases its slot in the experiment's pending counter, so the run can finish.
  #
  # Idempotent: a retried job reuses its existing Sample and skips grading that already ran.
  class SampleJob < ApplicationJob
    queue_as :default

    TRANSPORT_ERRORS = [ Faraday::ConnectionFailed, Faraday::TimeoutError, Net::OpenTimeout, Net::ReadTimeout ].freeze

    retry_on(*TRANSPORT_ERRORS, wait: 5.seconds, attempts: 2) do |job, error|
      Rails.logger.error("[SampleJob] transport error after retries: #{error.message}")
      job.release_slot(*job.arguments)
    end

    def perform(experiment_id, dataset_sample_id)
      experiment = Evaluation::Experiment.find(experiment_id)
      dataset_sample = Evaluation::DatasetSample.find(dataset_sample_id)

      run_sample(experiment, dataset_sample)
      finish_slot(experiment)
    rescue RubyLLM::Error => e
      Rails.logger.error("[SampleJob] sample #{dataset_sample_id} of experiment #{experiment_id} failed: #{e.message}")
      release_slot(experiment_id, dataset_sample_id)
    end

    # Drops the half-finished sample (so only fully graded samples count towards the completion
    # threshold) and releases the counter slot.
    def release_slot(experiment_id, dataset_sample_id)
      experiment = Evaluation::Experiment.find_by(id: experiment_id)
      return unless experiment

      experiment.samples.where(dataset_sample_id: dataset_sample_id).destroy_all
      finish_slot(experiment)
    end

    private

    def run_sample(experiment, dataset_sample)
      Evaluation::UsageScope.call(experiment) do
        sample = experiment.samples.find_by(dataset_sample_id: dataset_sample.id) ||
                 Evaluation::Sampler.call(experiment: experiment, dataset_sample: dataset_sample, prompt: experiment.prompt)
        grade(experiment, dataset_sample, sample)
      end
    end

    def grade(experiment, dataset_sample, sample)
      return if sample.evaluation_results.exists?

      grades = Evaluation::Grader.call(experiment: experiment, dataset_sample: dataset_sample, sample: sample)
      Evaluation::Grader::ResultWriter.call(grades: grades, experiment: experiment, dataset_sample: dataset_sample,
                                            sample: sample)
    end

    # The last slot closes the run: completed when the 80% threshold is met, failed otherwise.
    def finish_slot(experiment)
      experiment.with_lock do
        next if experiment.pending_samples_count <= 0

        experiment.decrement!(:pending_samples_count)
        next unless experiment.pending_samples_count.zero?

        experiment.may_complete? ? experiment.complete! : (experiment.fail! if experiment.may_fail?)
      end
    end
  end
end
