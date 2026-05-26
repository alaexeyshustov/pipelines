# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::EvaluationJob do
  include ActiveJob::TestHelper

  let(:experiment) { create(:evaluation_experiment, status: "evaluating") }
  let(:dataset_sample) { create(:evaluation_dataset_sample, dataset: experiment.dataset) }
  let(:sample) { create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample) }

  before do
    eval_stub = Class.new { define_method(:evaluate_and_store) { |*| nil } }.new
    allow(Evaluation::Evaluators::LLMJudgeEval).to receive(:new).and_return(eval_stub)
  end

  describe "#perform" do
    before { experiment.update!(pending_evaluations_count: 1) }

    it "invokes each evaluator's evaluate_and_store" do
      described_class.perform_now(experiment.id, sample.id)
      expect(Evaluation::Evaluators::LLMJudgeEval).to have_received(:new)
    end

    it "decrements pending_evaluations_count by one" do
      experiment.update!(pending_evaluations_count: 2)
      described_class.perform_now(experiment.id, sample.id)
      expect(experiment.reload.pending_evaluations_count).to eq(1)
    end

    context "when this is the last evaluation job (counter reaches zero)" do
      it "transitions the experiment to completed" do
        described_class.perform_now(experiment.id, sample.id)
        expect(experiment.reload).to be_completed
      end
    end

    context "when more evaluation jobs remain" do
      it "does not transition the experiment to completed" do
        experiment.update!(pending_evaluations_count: 2)
        described_class.perform_now(experiment.id, sample.id)
        expect(experiment.reload).to be_evaluating
      end
    end

    context "when evaluation begins while the experiment is still marked sampling" do
      it "transitions the experiment to evaluating before decrementing remaining work" do
        experiment.update!(
          status: "sampling",
          pending_samples_count: 0,
          pending_evaluations_count: 2
        )

        described_class.perform_now(experiment.id, sample.id)

        expect(experiment.reload).to be_evaluating
        expect(experiment.pending_evaluations_count).to eq(1)
      end
    end

    context "when retries are exhausted" do
      before do
        allow(Evaluation::Evaluators::LLMJudgeEval).to receive(:new).and_raise(RubyLLM::Error, "eval failed")
      end

      it "still decrements the counter on final failure" do
        perform_enqueued_jobs do
          described_class.perform_later(experiment.id, sample.id)
        end
        expect(experiment.reload.pending_evaluations_count).to eq(0)
      end

      it "transitions to completed when all evaluation jobs are done" do
        perform_enqueued_jobs do
          described_class.perform_later(experiment.id, sample.id)
        end
        expect(experiment.reload).to be_completed
      end
    end
  end
end
