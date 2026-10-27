require "rails_helper"

RSpec.describe Evaluation::PromptCreator do
  let(:attributes) { { name: "Emails::ClassifyAgent", system_prompt: "sys", user_prompt: "{{input}}", output_schema: nil } }

  describe ".call" do
    it "creates the prompt" do
      expect { described_class.call(**attributes) }.to change(Evaluation::Prompt, :count).by(1)
    end

    it "enqueues PromptAutoEvalJob for the new prompt" do
      prompt = described_class.call(**attributes)

      expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).with(prompt_id: prompt.id)
    end

    it "raises and does not enqueue when the prompt is invalid" do
      expect { described_class.call(**attributes, user_prompt: "") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Evaluation::PromptAutoEvalJob).not_to have_received(:perform_later)
    end
  end
end
