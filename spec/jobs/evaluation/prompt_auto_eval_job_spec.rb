require "rails_helper"

RSpec.describe Evaluation::PromptAutoEvalJob do
  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:dataset) { create(:leva_dataset) }
  let(:previous_prompt) { create(:leva_prompt, name: agent_name) }
  let(:previous_experiment) do
    create(:leva_experiment,
      prompt: previous_prompt,
      dataset: dataset,
      status: :completed,
      runner_class: "Evaluation::StubbedAgentRun",
      evaluator_classes: [ "LLMJudgeEval" ])
  end
  let(:new_prompt) { create(:leva_prompt, name: agent_name) }

  before { previous_experiment }

  describe "#perform" do
    it "creates a new experiment with the new prompt" do
      described_class.perform_now(new_prompt)
      new_exp = Leva::Experiment.where(prompt: new_prompt).first
      expect(new_exp).to be_present
      expect(new_exp.prompt).to eq(new_prompt)
    end

    it "reuses the previous experiment's dataset" do
      described_class.perform_now(new_prompt)
      new_exp = Leva::Experiment.where(prompt: new_prompt).first
      expect(new_exp.dataset).to eq(dataset)
    end

    it "sets runner_class and evaluator_classes on the new experiment" do
      described_class.perform_now(new_prompt)
      new_exp = Leva::Experiment.where(prompt: new_prompt).first
      expect(new_exp.runner_class).to eq("Evaluation::StubbedAgentRun")
      expect(new_exp.evaluator_classes).to eq([ "LLMJudgeEval" ])
    end

    it "enqueues Leva::ExperimentJob for the new experiment" do
      allow(Leva::ExperimentJob).to receive(:perform_later)
      described_class.perform_now(new_prompt)
      expect(Leva::ExperimentJob).to have_received(:perform_later).once
    end

    context "when no completed experiment exists for the prompt name" do
      let(:previous_experiment) do
        create(:leva_experiment, prompt: previous_prompt, dataset: dataset, status: :pending)
      end

      it "does not create an experiment" do
        expect { described_class.perform_now(new_prompt) }.not_to change(Leva::Experiment, :count)
      end

      it "does not enqueue Leva::ExperimentJob" do
        allow(Leva::ExperimentJob).to receive(:perform_later)
        described_class.perform_now(new_prompt)
        expect(Leva::ExperimentJob).not_to have_received(:perform_later)
      end
    end

    context "when no experiment exists for the prompt name at all" do
      let(:new_prompt) { create(:leva_prompt, name: "Records::FillAgent") }

      it "does nothing" do
        expect { described_class.perform_now(new_prompt) }.not_to change(Leva::Experiment, :count)
      end
    end
  end
end
