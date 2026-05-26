# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::ExperimentJob do
  describe "#perform" do
    let(:experiment) { create(:evaluation_experiment, status: "pending") }

    before { allow(Evaluation::SamplingJob).to receive(:perform_later) }

    it "transitions the experiment to sampling" do
      create(:evaluation_dataset_sample, dataset: experiment.dataset)
      described_class.perform_now(experiment)
      expect(experiment.reload).to be_sampling
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

    it "enqueues one SamplingJob per dataset sample" do
      create_list(:evaluation_dataset_sample, 3, dataset: experiment.dataset)
      described_class.perform_now(experiment)
      expect(Evaluation::SamplingJob).to have_received(:perform_later).exactly(3).times
    end

    it "does not re-enqueue sampling jobs when sampling is already in flight" do
      create_list(:evaluation_dataset_sample, 3, dataset: experiment.dataset)
      experiment.update!(status: "sampling", pending_samples_count: 2)
      job = described_class.new
      allow(job).to receive(:sampling_jobs_still_in_flight?).and_return(true)
      job.perform(experiment)
      expect(Evaluation::SamplingJob).not_to have_received(:perform_later)
    end

    it "re-enqueues sampling jobs when sampling state was set but jobs were never enqueued (crash recovery)" do
      create_list(:evaluation_dataset_sample, 2, dataset: experiment.dataset)
      experiment.update!(status: "sampling", pending_samples_count: 2)
      described_class.perform_now(experiment)
      expect(Evaluation::SamplingJob).to have_received(:perform_later).exactly(2).times
    end

    it "re-enqueues only missing sampling jobs when sampling was partially enqueued before a crash" do
      dataset_samples = create_list(:evaluation_dataset_sample, 3, dataset: experiment.dataset)
      create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_samples.first)
      experiment.update!(status: "sampling", pending_samples_count: 2)
      job = described_class.new.tap { |instance| allow(instance).to receive(:sampling_jobs_still_in_flight?).and_return(false) }
      job.perform(experiment)
      expect(Evaluation::SamplingJob).to have_received(:perform_later)
        .with(experiment.id, dataset_samples.second.id)
      expect(Evaluation::SamplingJob).to have_received(:perform_later)
        .with(experiment.id, dataset_samples.third.id)
      expect(Evaluation::SamplingJob).to have_received(:perform_later).exactly(2).times
    end

    it "does nothing when the experiment is already completed" do
      experiment.update!(status: "completed")
      described_class.perform_now(experiment)
      expect(Evaluation::SamplingJob).not_to have_received(:perform_later)
    end

    it "does nothing when the experiment is already failed" do
      experiment.update!(status: "failed")
      described_class.perform_now(experiment)
      expect(Evaluation::SamplingJob).not_to have_received(:perform_later)
    end
  end
end
