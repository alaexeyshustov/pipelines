require "rails_helper"

RSpec.describe "Evaluation::AgentDefaultPrompt" do
  subject(:agent_default) { Evaluation::AgentDefaultPrompt.new(system_prompt: "sys", user_prompt: "") }

  it "labels itself 'Agent default'" do
    expect(agent_default.label).to eq("Agent default")
  end

  it "exposes the system and user prompt" do
    expect(agent_default).to have_attributes(system_prompt: "sys", user_prompt: "")
  end
end
