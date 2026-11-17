require "rails_helper"

RSpec.describe Evaluation::ImproveFailureLogger do
  let(:experiment) { create(:evaluation_experiment) }
  let(:error) { StandardError.new("LLM call failed") }

  describe ".call" do
    it "logs the context, experiment id, and error message" do
      allow(Rails.logger).to receive(:error)

      result = described_class.call(context: "PromptImprover failed", experiment: experiment, error: error)

      message = "PromptImprover failed for experiment #{experiment.id}: LLM call failed"
      expect(Rails.logger).to have_received(:error).with(message)
      expect(result.message).to eq(message)
    end
  end
end
