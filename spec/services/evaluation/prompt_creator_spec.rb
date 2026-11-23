require "rails_helper"

RSpec.describe Evaluation::PromptCreator do
  let(:attributes) { { name: "Emails::ClassifyAgent", system_prompt: "sys", user_prompt: "{{input}}", output_schema: nil } }

  describe ".call" do
    it "creates the prompt" do
      expect { described_class.call(**attributes) }.to change(Evaluation::Prompt, :count).by(1)
    end

    it "enqueues PromptAutoEvalJob for the new prompt" do
      expect { described_class.call(**attributes) }
        .to(have_enqueued_job(Evaluation::PromptAutoEvalJob).with { |prompt_id:| expect(prompt_id).to eq(Evaluation::Prompt.last.id) })
    end

    it "raises and does not enqueue when the prompt is invalid" do
      expect { described_class.call(**attributes, user_prompt: "") }
        .to raise_error(ActiveRecord::RecordInvalid).and not_have_enqueued_job(Evaluation::PromptAutoEvalJob)
    end
  end
end
