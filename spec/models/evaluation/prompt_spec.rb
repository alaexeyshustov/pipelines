require "rails_helper"

RSpec.describe Evaluation::Prompt do
  it "enqueues PromptAutoEvalJob when a new prompt is created" do
    prompt = create(:orchestration_prompt)
    expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).with(prompt_id: prompt.id)
  end

  it "does not enqueue PromptAutoEvalJob when an existing prompt is updated" do
    prompt = create(:orchestration_prompt)
    original_version = prompt.version

    prompt.update!(system_prompt: "Updated prompt text")

    # Exactly 1 call total (from create); update must not have triggered another
    expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).exactly(1).time
    expect(prompt.reload.version).to eq(original_version)
  end

  it "increments the version for new prompts with the same name" do
    create(:orchestration_prompt, name: "Emails::ClassifyAgent")

    prompt = create(:orchestration_prompt, name: "Emails::ClassifyAgent")

    expect(prompt.version).to eq(2)
  end
end
