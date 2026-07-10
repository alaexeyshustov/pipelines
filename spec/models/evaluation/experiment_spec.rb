# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Experiment do
  describe "schema" do
    it "does not have a runner_class column" do
      expect(described_class.column_names).not_to include("runner_class")
    end

    it "does not have an evaluator_classes column" do
      expect(described_class.column_names).not_to include("evaluator_classes")
    end
  end

  describe ".completed_for_prompt_name" do
    let(:prompt) { create(:orchestration_prompt, name: "classifier") }
    let(:other_prompt) { create(:orchestration_prompt, name: "summarizer") }

    it "returns completed experiments matching the prompt name" do
      match = create(:evaluation_experiment, prompt: prompt, status: "completed")
      create(:evaluation_experiment, prompt: prompt, status: "pending")
      create(:evaluation_experiment, prompt: other_prompt, status: "completed")

      expect(described_class.completed_for_prompt_name("classifier")).to contain_exactly(match)
    end

    it "excludes experiments for a different prompt name" do
      create(:evaluation_experiment, prompt: other_prompt, status: "completed")

      expect(described_class.completed_for_prompt_name("classifier")).to be_empty
    end

    it "excludes non-completed experiments for the same prompt name" do
      create(:evaluation_experiment, prompt: prompt, status: "sampling")

      expect(described_class.completed_for_prompt_name("classifier")).to be_empty
    end
  end

  describe ".sibling_for_prompt_name" do
    let(:prompt) { create(:orchestration_prompt, name: "classifier") }
    let(:other_prompt) { create(:orchestration_prompt, name: "summarizer") }

    it "returns experiments matching the prompt name regardless of status" do
      completed = create(:evaluation_experiment, prompt: prompt, status: "completed")
      pending = create(:evaluation_experiment, prompt: prompt, status: "pending")

      expect(described_class.sibling_for_prompt_name("classifier", excluding_id: -1))
        .to contain_exactly(completed, pending)
    end

    it "excludes the given id" do
      excluded = create(:evaluation_experiment, prompt: prompt, status: "completed")
      other = create(:evaluation_experiment, prompt: prompt, status: "completed")

      expect(described_class.sibling_for_prompt_name("classifier", excluding_id: excluded.id))
        .to contain_exactly(other)
    end

    it "excludes experiments for a different prompt name" do
      create(:evaluation_experiment, prompt: other_prompt, status: "completed")

      expect(described_class.sibling_for_prompt_name("classifier", excluding_id: -1)).to be_empty
    end
  end

  describe "AASM state machine" do
    subject(:experiment) { create(:evaluation_experiment, status: "pending") }

    it "starts in the pending state" do
      expect(experiment).to be_pending
    end

    it "transitions pending → sampling" do
      experiment.start_sampling!
      expect(experiment.reload).to be_sampling
    end

    it "transitions sampling → evaluating" do
      experiment.update!(status: "sampling", pending_samples_count: 0, pending_evaluations_count: 1)
      experiment.start_evaluating!
      expect(experiment.reload).to be_evaluating
    end

    it "transitions evaluating → completed" do
      experiment.update!(status: "evaluating", pending_evaluations_count: 0)
      experiment.complete!
      expect(experiment.reload).to be_completed
    end

    it "transitions pending → failed" do
      experiment.fail!
      expect(experiment.reload).to be_failed
    end

    it "transitions sampling → failed" do
      experiment.update!(status: "sampling")
      experiment.fail!
      expect(experiment.reload).to be_failed
    end

    it "transitions evaluating → failed" do
      experiment.update!(status: "evaluating")
      experiment.fail!
      expect(experiment.reload).to be_failed
    end

    it "raises on an invalid transition from pending to completed" do
      expect { experiment.complete! }.to raise_error(AASM::InvalidTransition)
    end

    it "raises on an invalid transition from pending to evaluating" do
      expect { experiment.start_evaluating! }.to raise_error(AASM::InvalidTransition)
    end

    it "raises on an invalid transition from sampling to evaluating while sampling is still in flight" do
      experiment.update!(status: "sampling", pending_samples_count: 1, pending_evaluations_count: 1)
      expect { experiment.start_evaluating! }.to raise_error(AASM::InvalidTransition)
    end

    it "raises on an invalid transition from evaluating to completed while evaluations are still pending" do
      experiment.update!(status: "evaluating", pending_evaluations_count: 1)
      expect { experiment.complete! }.to raise_error(AASM::InvalidTransition)
    end
  end
end
