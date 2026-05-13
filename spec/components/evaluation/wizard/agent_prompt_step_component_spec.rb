# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Wizard::AgentPromptStepComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(agent_names: agent_names, prompts: prompts))
  end

  let(:agent_names) { %w[Emails::ClassifyAgent Chats::SummaryAgent] }
  let(:prompts) { build_list(:orchestration_prompt, 2) }


  it "renders a form posting to wizard_step" do
    expect(rendered.css("form").first["action"]).to include("wizard_step")
  end

  it "renders agent name options" do
    agent_names.each { |name| expect(rendered.text).to include(name) }
  end

  it "renders experiment name field" do
    expect(rendered.css("input[name*='experiment_name']")).to be_present
  end

  it "pre-fills agent_name when provided" do
    rendered = render_inline(described_class.new(
      agent_names: agent_names,
      prompts: prompts,
      agent_name: "Emails::ClassifyAgent"
    ))
    selected = rendered.css("option[selected]").first
    expect(selected&.text).to eq("Emails::ClassifyAgent")
  end

  it "pre-fills experiment_name when provided" do
    rendered = render_inline(described_class.new(
      agent_names: agent_names,
      prompts: prompts,
      experiment_name: "My Eval Run"
    ))
    expect(rendered.css("input[name*='experiment_name']").first["value"]).to eq("My Eval Run")
  end

  it "renders a Next button" do
    expect(rendered.css("button[type='submit']").text).to include("Next")
  end
end
