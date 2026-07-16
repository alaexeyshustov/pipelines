
require "rails_helper"

RSpec.describe Evaluation::Improvement::GetExperimentPromptTool do
  subject(:tool) { described_class.new }

  describe "#execute" do
    context "when the experiment has a complete prompt" do
      let(:schema) { { "type" => "object" } }
      let(:prompt) do
        create(:orchestration_prompt,
               system_prompt: "You are a classifier.",
               user_prompt: "Classify this email: {{input}}",
               output_schema: schema)
      end
      let(:experiment) { create(:evaluation_experiment, prompt: prompt) }

      it "returns system_prompt, user_prompt, and output_schema for the experiment" do
        result = tool.execute(experiment_id: experiment.id)
        expect(result).to eq(
          system_prompt: "You are a classifier.",
          user_prompt: "Classify this email: {{input}}",
          output_schema: schema
        )
      end
    end

    it "coerces nil system_prompt to an empty string" do
      prompt = create(:orchestration_prompt, system_prompt: nil, user_prompt: "user prompt")
      experiment = create(:evaluation_experiment, prompt: prompt)

      result = tool.execute(experiment_id: experiment.id)

      expect(result[:system_prompt]).to eq("")
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
