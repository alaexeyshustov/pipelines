# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::RunEvalJob do
  let(:experiment) { create(:evaluation_experiment, status: :running) }
  let(:dataset_record) { create(:evaluation_dataset_record, dataset: experiment.dataset) }

  let(:runner_result) { create(:evaluation_runner_result, experiment: experiment, dataset_record: dataset_record) }

  before do
    runner_double = instance_double(Evaluation::Runners::StubbedAgentRun)
    allow(runner_double).to receive(:execute_and_store).and_return(runner_result)
    allow(Evaluation::Runners::StubbedAgentRun).to receive(:new).and_return(runner_double)

    eval_double = instance_double(Evaluation::Evaluators::LLMJudgeEval)
    allow(eval_double).to receive(:evaluate_and_store)
    allow(Evaluation::Evaluators::LLMJudgeEval).to receive(:new).and_return(eval_double)
  end

  describe "#perform" do
    it "invokes the runner's execute_and_store" do
      described_class.perform_now(experiment.id, dataset_record.id)
      expect(Evaluation::Runners::StubbedAgentRun).to have_received(:new)
    end

    it "invokes each evaluator's evaluate_and_store" do
      described_class.perform_now(experiment.id, dataset_record.id)
      expect(Evaluation::Evaluators::LLMJudgeEval).to have_received(:new)
    end

    it "marks the experiment as completed when all records have been processed" do
      # This is the only dataset record, so it is the last one
      described_class.perform_now(experiment.id, dataset_record.id)
      expect(experiment.reload.status).to eq("completed")
    end

    it "does not mark the experiment as completed when more records remain" do
      create(:evaluation_dataset_record, dataset: experiment.dataset)
      described_class.perform_now(experiment.id, dataset_record.id)
      expect(experiment.reload.status).to eq("running")
    end
  end
end
