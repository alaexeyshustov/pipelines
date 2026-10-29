require "rails_helper"

RSpec.describe Evaluation::SampleJob do
  include ActiveJob::TestHelper

  let(:dataset) { create(:evaluation_dataset) }
  let(:experiment) { create(:evaluation_experiment, status: "running", dataset: dataset, pending_samples_count: 1) }
  let(:dataset_sample) { create(:evaluation_dataset_sample, dataset: dataset) }
  let(:sample) { experiment.samples.find_by!(dataset_sample_id: dataset_sample.id) }
  let(:scoped_owners) { [] }

  before do
    owners = scoped_owners
    stub_const("Evaluation::UsageScope", Module.new do
      define_singleton_method(:call) do |owner, &block|
        owners << owner
        block.call
      end
    end)
    allow(Evaluation::Sampler).to receive(:call) do |experiment:, dataset_sample:, **|
      create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample)
    end
    allow(Evaluation::Grader).to receive(:call).and_return([])
    allow(Evaluation::Grader::ResultWriter).to receive(:call).and_return([])
  end

  describe "#perform" do
    it "samples with the experiment prompt" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(Evaluation::Sampler).to have_received(:call)
        .with(experiment: experiment, dataset_sample: dataset_sample, prompt: experiment.prompt)
    end

    it "grades and persists the grades" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(Evaluation::Grader::ResultWriter).to have_received(:call)
        .with(grades: [], experiment: experiment, dataset_sample: dataset_sample, sample: sample)
    end

    it "runs inside the experiment usage scope" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(scoped_owners).to eq([ experiment ])
    end

    it "decrements pending_samples_count by one" do
      experiment.update!(pending_samples_count: 2)
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(experiment.reload.pending_samples_count).to eq(1)
    end

    it "keeps the experiment running while samples remain" do
      experiment.update!(pending_samples_count: 2)
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(experiment.reload).to be_running
    end

    it "completes the experiment when the last sample finishes above the threshold" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(experiment.reload).to be_completed
    end

    it "completes at exactly 80% of samples" do
      others = create_list(:evaluation_dataset_sample, 4, dataset: dataset)
      others.first(3).each { |ds| create(:evaluation_sample, experiment: experiment, dataset_sample: ds) }
      described_class.perform_now(experiment.id, others.last.id)
      expect(experiment.reload).to be_completed
    end

    it "fails the experiment when fewer than 80% of samples succeeded" do
      create_list(:evaluation_dataset_sample, 4, dataset: dataset)
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(experiment.reload).to be_failed
    end

    it "reuses an existing sample and skips grading that already ran" do
      existing = create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample)
      create(:evaluation_evaluation_result, sample: existing, dataset_sample: dataset_sample)
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(Evaluation::Sampler).not_to have_received(:call)
      expect(Evaluation::Grader).not_to have_received(:call)
    end
  end

  describe "when RubyLLM fails (already retried by RubyLLM)" do
    before do
      allow(Evaluation::Grader).to receive(:call).and_raise(RubyLLM::Error, "judge failed")
      create(:evaluation_dataset_sample, dataset: dataset)
    end

    it "does not retry the job" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(Evaluation::Grader).to have_received(:call).once
    end

    it "releases the slot and drops the ungraded sample" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(experiment.reload.pending_samples_count).to eq(0)
      expect(experiment.samples).to be_empty
    end

    it "fails the run when below the threshold" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(experiment.reload).to be_failed
    end
  end

  describe "when a transport error persists" do
    before do
      allow(Evaluation::Sampler).to receive(:call).and_raise(Faraday::ConnectionFailed, "down")
    end

    it "retries once, then releases the slot" do
      perform_enqueued_jobs { described_class.perform_later(experiment.id, dataset_sample.id) }
      expect(Evaluation::Sampler).to have_received(:call).twice
      expect(experiment.reload.pending_samples_count).to eq(0)
    end
  end
end
