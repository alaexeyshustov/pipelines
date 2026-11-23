require "rails_helper"

RSpec.describe Evaluation::ExperimentJob do
  describe "#perform" do
    let(:experiment) { create(:evaluation_experiment, status: "pending") }

    it "transitions the experiment to running" do
      create(:evaluation_dataset_sample, dataset: experiment.dataset)
      described_class.perform_now(experiment)
      expect(experiment.reload).to be_running
    end

    it "transitions the experiment to failed when the dataset has no samples" do
      described_class.perform_now(experiment)
      expect(experiment.reload).to be_failed
    end

    it "sets pending_samples_count to the number of dataset samples" do
      create_list(:evaluation_dataset_sample, 3, dataset: experiment.dataset)
      described_class.perform_now(experiment)
      expect(experiment.reload.pending_samples_count).to eq(3)
    end

    it "enqueues one SampleJob per dataset sample" do
      create_list(:evaluation_dataset_sample, 3, dataset: experiment.dataset)
      expect { described_class.perform_now(experiment) }.to have_enqueued_job(Evaluation::SampleJob).exactly(3).times
    end

    it "does not re-enqueue sample jobs when jobs are already in flight" do
      create_list(:evaluation_dataset_sample, 3, dataset: experiment.dataset)
      experiment.update!(status: "running", pending_samples_count: 2)
      job = described_class.new
      allow(job).to receive(:sample_jobs_still_in_flight?).and_return(true)
      expect { job.perform(experiment) }.not_to have_enqueued_job(Evaluation::SampleJob)
    end

    it "re-enqueues sample jobs when running state was set but jobs were never enqueued (crash recovery)" do
      create_list(:evaluation_dataset_sample, 2, dataset: experiment.dataset)
      experiment.update!(status: "running", pending_samples_count: 2)
      expect { described_class.perform_now(experiment) }.to have_enqueued_job(Evaluation::SampleJob).exactly(2).times
    end

    it "re-enqueues only missing sample jobs after a partial enqueue crash" do
      dataset_samples = create_list(:evaluation_dataset_sample, 3, dataset: experiment.dataset)
      create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_samples.first)
      experiment.update!(status: "running", pending_samples_count: 2)
      job = described_class.new.tap { |instance| allow(instance).to receive(:sample_jobs_still_in_flight?).and_return(false) }
      expect { job.perform(experiment) }
        .to have_enqueued_job(Evaluation::SampleJob).with(experiment.id, dataset_samples.second.id)
        .and have_enqueued_job(Evaluation::SampleJob).with(experiment.id, dataset_samples.third.id)
        .and have_enqueued_job(Evaluation::SampleJob).exactly(2).times
    end

    it "resets pending_samples_count to the work left on crash recovery" do
      dataset_samples = create_list(:evaluation_dataset_sample, 3, dataset: experiment.dataset)
      create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_samples.first)
      experiment.update!(status: "running", pending_samples_count: 3)
      described_class.perform_now(experiment)
      expect(experiment.reload.pending_samples_count).to eq(2)
    end

    it "does nothing when the experiment is already completed" do
      experiment.update!(status: "completed")
      expect { described_class.perform_now(experiment) }.not_to have_enqueued_job(Evaluation::SampleJob)
    end

    it "does nothing when the experiment is already failed" do
      experiment.update!(status: "failed")
      expect { described_class.perform_now(experiment) }.not_to have_enqueued_job(Evaluation::SampleJob)
    end
  end
end
