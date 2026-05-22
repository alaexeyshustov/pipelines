# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::ExperimentJob do
  describe "#perform" do
    let(:experiment) { create(:evaluation_experiment, status: :pending) }

    before { allow(Evaluation::RunEvalJob).to receive(:set).and_return(double(perform_later: nil)) }

    it "sets the experiment status to running" do
      described_class.perform_now(experiment)
      expect(experiment.reload.status).to eq("running")
    end

    it "enqueues one RunEvalJob per dataset record" do
      create_list(:evaluation_dataset_sample, 3, dataset: experiment.dataset)
      described_class.perform_now(experiment)
      expect(Evaluation::RunEvalJob).to have_received(:set).exactly(3).times
    end

    it "does nothing when the experiment is already completed" do
      experiment.update!(status: :completed)
      described_class.perform_now(experiment)
      expect(Evaluation::RunEvalJob).not_to have_received(:set)
    end

    it "does nothing when the experiment is already running" do
      experiment.update!(status: :running)
      described_class.perform_now(experiment)
      expect(Evaluation::RunEvalJob).not_to have_received(:set)
    end
  end
end
