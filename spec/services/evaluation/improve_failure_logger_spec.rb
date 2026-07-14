# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::ImproveFailureLogger do
  let(:experiment) { create(:evaluation_experiment) }
  let(:error) { StandardError.new("LLM call failed") }

  describe ".call" do
    it "logs the context, experiment id, and error message" do
      allow(Rails.logger).to receive(:error)

      described_class.call(context: "PromptImprover failed", experiment: experiment, error: error)

      expect(Rails.logger).to have_received(:error)
        .with("PromptImprover failed for experiment #{experiment.id}: LLM call failed")
    end
  end
end
