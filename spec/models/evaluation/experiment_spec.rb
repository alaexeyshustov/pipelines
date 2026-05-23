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
      experiment.update!(status: "sampling")
      experiment.start_evaluating!
      expect(experiment.reload).to be_evaluating
    end

    it "transitions evaluating → completed" do
      experiment.update!(status: "evaluating")
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
  end
end
