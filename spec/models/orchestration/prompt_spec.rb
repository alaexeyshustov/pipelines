require "rails_helper"

RSpec.describe Orchestration::Prompt do
  it "enqueues PromptAutoEvalJob when a new prompt is created" do
    prompt = create(:orchestration_prompt)
    expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).with(prompt.id)
  end

  it "does not enqueue PromptAutoEvalJob when an existing prompt is updated" do
    prompt = create(:orchestration_prompt)
    RSpec::Mocks.space.proxy_for(Evaluation::PromptAutoEvalJob).reset
    allow(Evaluation::PromptAutoEvalJob).to receive(:perform_later)

    prompt.update!(system_prompt: "Updated prompt text")

    expect(Evaluation::PromptAutoEvalJob).not_to have_received(:perform_later)
  end
end
