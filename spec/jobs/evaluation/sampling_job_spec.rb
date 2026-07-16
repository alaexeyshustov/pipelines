
require "rails_helper"

RSpec.describe Evaluation::SamplingJob do
  include ActiveJob::TestHelper

  let(:dataset) { create(:evaluation_dataset) }
  let(:experiment) { create(:evaluation_experiment, status: "sampling", dataset: dataset) }
  let(:dataset_sample) { create(:evaluation_dataset_sample, dataset: dataset) }
  let(:sample) { create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample) }

  before do
    the_sample = sample
    allow(Evaluation::Sampler).to receive(:call).and_return(the_sample)
    allow(Evaluation::EvaluationJob).to receive(:perform_later)
  end

  describe "#perform" do
    before { experiment.update!(pending_samples_count: 1) }

    it "calls Evaluation::Sampler with the correct arguments" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(Evaluation::Sampler).to have_received(:call)
        .with(experiment: experiment, dataset_sample: dataset_sample, prompt: experiment.prompt)
    end

    it "decrements pending_samples_count by one" do
      experiment.update!(pending_samples_count: 2)
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(experiment.reload.pending_samples_count).to eq(1)
    end

    context "when the last sampling job completes and threshold is met" do
      it "transitions the experiment to evaluating" do
        described_class.perform_now(experiment.id, dataset_sample.id)
        expect(experiment.reload).to be_evaluating
      end

      it "sets pending_evaluations_count to the number of samples" do
        described_class.perform_now(experiment.id, dataset_sample.id)
        expect(experiment.reload.pending_evaluations_count).to eq(1)
      end

      it "enqueues one EvaluationJob per sample" do
        described_class.perform_now(experiment.id, dataset_sample.id)
        expect(Evaluation::EvaluationJob).to have_received(:perform_later)
          .with(experiment.id, sample.id)
      end
    end

    context "when exactly 80% of samples complete (boundary passes)" do
      it "transitions to evaluating" do
        extra_ds = create_list(:evaluation_dataset_sample, 4, dataset: dataset)
        create(:evaluation_sample, experiment: experiment, dataset_sample: extra_ds[0])
        create(:evaluation_sample, experiment: experiment, dataset_sample: extra_ds[1])
        create(:evaluation_sample, experiment: experiment, dataset_sample: extra_ds[2])

        described_class.perform_now(experiment.id, extra_ds[3].id)

        expect(experiment.reload).to be_evaluating
      end
    end

    context "when fewer than 80% of samples complete" do
      it "transitions the experiment to failed" do
        create_list(:evaluation_dataset_sample, 5, dataset: dataset)

        described_class.perform_now(experiment.id, dataset_sample.id)

        expect(experiment.reload).to be_failed
      end
    end

    context "when retries are exhausted" do
      before do
        allow(Evaluation::Sampler).to receive(:call).and_raise(RubyLLM::Error, "sampling failed")
        create(:evaluation_dataset_sample, dataset: dataset)
      end

      it "decrements the counter on final failure" do
        perform_enqueued_jobs do
          described_class.perform_later(experiment.id, dataset_sample.id)
        end
        expect(experiment.reload.pending_samples_count).to eq(0)
      end

      it "transitions to failed when below threshold after retries exhausted" do
        perform_enqueued_jobs do
          described_class.perform_later(experiment.id, dataset_sample.id)
        end
        expect(experiment.reload).to be_failed
      end
    end
  end
end
