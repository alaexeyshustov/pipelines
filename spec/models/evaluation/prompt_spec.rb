require "rails_helper"

RSpec.describe Evaluation::Prompt do
  it "enqueues PromptAutoEvalJob when a new prompt is created" do
    prompt = create(:orchestration_prompt)
    expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).with(prompt_id: prompt.id)
  end

  it "does not enqueue PromptAutoEvalJob when an existing prompt is updated" do
    prompt = create(:orchestration_prompt)

    prompt.update!(system_prompt: "Updated prompt text")

    # Exactly 1 call total (from create); update must not have triggered another
    expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).exactly(1).time
  end
end
