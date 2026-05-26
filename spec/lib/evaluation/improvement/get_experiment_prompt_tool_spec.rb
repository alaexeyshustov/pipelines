# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Improvement::GetExperimentPromptTool do
  subject(:tool) { described_class.new }

  describe "#execute" do
    it "returns system_prompt and user_prompt for the experiment" do
      prompt = create(:orchestration_prompt,
                      system_prompt: "You are a classifier.",
                      user_prompt: "Classify this email: {{input}}")
      experiment = create(:evaluation_experiment, prompt: prompt)

      result = tool.execute(experiment_id: experiment.id)

      expect(result).to eq(
        system_prompt: "You are a classifier.",
        user_prompt: "Classify this email: {{input}}"
      )
    end

    it "returns nil when the experiment does not exist" do
      expect(tool.execute(experiment_id: 0)).to be_nil
    end

    it "returns nil when the experiment has no prompt" do
      experiment = create(:evaluation_experiment, prompt: nil)

      expect(tool.execute(experiment_id: experiment.id)).to be_nil
    end
  end
end
