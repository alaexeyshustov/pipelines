
require "rails_helper"

RSpec.describe Evaluation::Wizard::AgentPromptStepComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(form: build_form)) }

  let!(:prompts) do
    [
      create(:orchestration_prompt, name: "Emails::ClassifyAgent"),
      create(:orchestration_prompt, name: "Chats::SummaryAgent")
    ]
  end
  let(:agent_names) { prompts.map(&:name).sort }

  def build_form(overrides = {})
    payload = {
      "agent_name"      => overrides.fetch(:agent_name, nil),
      "prompt_id"       => overrides.fetch(:prompt_id, nil),
      "experiment_name" => overrides.fetch(:experiment_name, nil),
      "sample_model"    => overrides.fetch(:sample_model, nil),
      "evaluation_model" => overrides.fetch(:evaluation_model, nil)
    }
    Evaluation::Wizard::Step1Form.new(draft_payload: payload)
  end

  it "renders a form posting to evaluation_experiments_path" do
    expect(rendered.css("form").first["action"]).to include("/evaluation/experiments")
  end

  it "renders agent name options" do
    agent_names.each { |name| expect(rendered.text).to include(name) }
  end

  it "renders experiment name field" do
    expect(rendered.css("input[name*='experiment_name']")).to be_present
  end

  it "pre-fills agent_name when provided" do
    rendered = render_inline(described_class.new(form: build_form(agent_name: "Emails::ClassifyAgent")))
    selected = rendered.css("option[selected]").first
    expect(selected&.text).to eq("Emails::ClassifyAgent")
  end

  it "pre-fills experiment_name when provided" do
    rendered = render_inline(described_class.new(form: build_form(experiment_name: "My Eval Run")))
    expect(rendered.css("input[name*='experiment_name']").first["value"]).to eq("My Eval Run")
  end

  it "renders a Next button" do
    expect(rendered.css("button[type='submit']").text).to include("Next")
  end

  describe "edit panel" do
    it "renders an edit toggle button wired to toggleEdit" do
      expect(rendered.css("button[data-action*='toggleEdit']")).to be_present
    end

    it "renders the edit panel with the editPanel target" do
      expect(rendered.css("[data-agent-select-target='editPanel']")).to be_present
    end

    it "renders a system_prompt textarea in the edit panel" do
      expect(rendered.css("textarea[data-agent-select-target='systemPromptField']")).to be_present
    end

    it "renders a user_prompt textarea in the edit panel" do
      expect(rendered.css("textarea[data-agent-select-target='userPromptField']")).to be_present
    end

    it "renders an output_schema textarea in the edit panel" do
      expect(rendered.css("textarea[data-agent-select-target='outputSchemaField']")).to be_present
    end

    it "exposes fork_prompt_url as a Stimulus value on the form" do
      expect(rendered.css("form[data-agent-select-fork-prompt-url-value]")).to be_present
    end

    it "exposes prompt_content_url as a Stimulus value on the form" do
      expect(rendered.css("form[data-agent-select-prompt-content-url-value]")).to be_present
    end

    it "wires the submit button to the submitButton target" do
      expect(rendered.css("button[type='submit'][data-agent-select-target='submitButton']")).to be_present
    end
  end

  context "with available_models" do
    let(:real_models)   { Orchestration::Agent.available_models }
    let(:first_provider) { real_models.first[0] }
    let(:first_model)    { real_models.first[1].first }

    it "renders a sample_model dropdown" do
      expect(rendered.css("select[name='wizard[sample_model]']")).to be_present
    end

    it "renders an evaluation_model dropdown" do
      expect(rendered.css("select[name='wizard[evaluation_model]']")).to be_present
    end

    it "renders model options in both dropdowns" do
      select_names = rendered.css("select[name='wizard[sample_model]'] option, select[name='wizard[evaluation_model]'] option")
                             .map(&:text)
      expect(select_names).to include("#{first_provider} / #{first_model}")
    end

    it "includes a blank default option in both dropdowns" do
      sample_blank     = rendered.css("select[name='wizard[sample_model]'] option[value='']").first
      evaluation_blank = rendered.css("select[name='wizard[evaluation_model]'] option[value='']").first
      expect(sample_blank.text).to include("Use default")
      expect(evaluation_blank.text).to include("Use default")
    end

    it "pre-selects sample_model when provided" do
      rendered = render_inline(described_class.new(form: build_form(sample_model: first_model)))
      selected = rendered.css("select[name='wizard[sample_model]'] option[selected]").first
      expect(selected&.attribute("value")&.value).to eq(first_model)
    end

    it "pre-selects evaluation_model when provided" do
      rendered = render_inline(described_class.new(form: build_form(evaluation_model: first_model)))
      selected = rendered.css("select[name='wizard[evaluation_model]'] option[selected]").first
      expect(selected&.attribute("value")&.value).to eq(first_model)
    end
  end
end
