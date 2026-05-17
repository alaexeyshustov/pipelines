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

  context "with available_models" do
    subject(:rendered) do
      render_inline(described_class.new(
        agent_names: agent_names,
        prompts: prompts,
        available_models: available_models
      ))
    end

    let(:available_models) { [ [ "openai", [ "gpt-4o", "gpt-4o-mini" ] ], [ "mistral", [ "mistral-large-latest" ] ] ] }


    it "renders a sample_model dropdown" do
      expect(rendered.css("select[name='wizard[sample_model]']")).to be_present
    end

    it "renders an evaluation_model dropdown" do
      expect(rendered.css("select[name='wizard[evaluation_model]']")).to be_present
    end

    it "renders model options in both dropdowns" do
      select_names = rendered.css("select[name='wizard[sample_model]'] option, select[name='wizard[evaluation_model]'] option")
                             .map(&:text)
      expect(select_names).to include("openai / gpt-4o", "mistral / mistral-large-latest")
    end

    it "includes a blank default option in both dropdowns" do
      sample_blank     = rendered.css("select[name='wizard[sample_model]'] option[value='']").first
      evaluation_blank = rendered.css("select[name='wizard[evaluation_model]'] option[value='']").first
      expect(sample_blank.text).to include("Use default")
      expect(evaluation_blank.text).to include("Use default")
    end

    it "pre-selects sample_model when provided" do
      rendered = render_inline(described_class.new(
        agent_names: agent_names,
        prompts: prompts,
        available_models: available_models,
        sample_model: "gpt-4o"
      ))
      selected = rendered.css("select[name='wizard[sample_model]'] option[selected]").first
      expect(selected&.attribute("value")&.value).to eq("gpt-4o")
    end

    it "pre-selects evaluation_model when provided" do
      rendered = render_inline(described_class.new(
        agent_names: agent_names,
        prompts: prompts,
        available_models: available_models,
        evaluation_model: "mistral-large-latest"
      ))
      selected = rendered.css("select[name='wizard[evaluation_model]'] option[selected]").first
      expect(selected&.attribute("value")&.value).to eq("mistral-large-latest")
    end
  end
end
