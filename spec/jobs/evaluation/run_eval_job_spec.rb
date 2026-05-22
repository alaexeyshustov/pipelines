# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::RunEvalJob do
  let(:experiment) { create(:evaluation_experiment, status: :running) }
  let(:dataset_sample) { create(:evaluation_dataset_sample, dataset: experiment.dataset) }
  let(:sample) { create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample) }

  before do
    the_sample = sample
    allow(Evaluation::Sampler).to receive(:call).and_return(the_sample)

    eval_stub = Class.new { define_method(:evaluate_and_store) { |*| nil } }.new
    allow(Evaluation::Evaluators::LLMJudgeEval).to receive(:new).and_return(eval_stub)
  end

  describe "#perform" do
    it "invokes Evaluation::Sampler.call" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(Evaluation::Sampler).to have_received(:call)
        .with(experiment: experiment, dataset_sample: dataset_sample, prompt: experiment.prompt)
    end

    it "invokes each evaluator's evaluate_and_store" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(Evaluation::Evaluators::LLMJudgeEval).to have_received(:new)
    end

    it "marks the experiment as completed when all samples have been processed" do
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(experiment.reload.status).to eq("completed")
    end

    it "does not mark the experiment as completed when more samples remain" do
      create(:evaluation_dataset_sample, dataset: experiment.dataset)
      described_class.perform_now(experiment.id, dataset_sample.id)
      expect(experiment.reload.status).to eq("running")
    end
  end
end
