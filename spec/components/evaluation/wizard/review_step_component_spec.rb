# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Wizard::ReviewStepComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(form: build_form)) }

  let(:prompt)  { create(:orchestration_prompt, name: "classify_agent") }
  let(:dataset) { create(:evaluation_dataset, name: "emails_dataset") }

  def build_form(overrides = {})
    payload = {
      "agent_name"      => "Emails::ClassifyAgent",
      "experiment_name" => "My Eval",
      "prompt_id"       => overrides.fetch(:prompt_id, prompt.id),
      "dataset_id"      => overrides.fetch(:dataset_id, dataset.id)
    }
    Evaluation::Wizard::Step4Form.new(draft_payload: payload)
  end

  it "renders the experiment name" do
    expect(rendered.text).to include("My Eval")
  end

  it "renders the agent name" do
    expect(rendered.text).to include("Emails::ClassifyAgent")
  end

  it "renders the dataset name" do
    expect(rendered.text).to include("emails_dataset")
  end

  it "renders the metrics count" do
    create_list(:evaluation_metric, 4, agent_name: "Emails::ClassifyAgent", active: true)
    expect(render_inline(described_class.new(form: build_form)).text).to include("4")
  end

  it "renders a Run Experiment submit button" do
    expect(rendered.css("button[type='submit']").text).to include("Run")
  end

  it "enables the submit button when metrics are present" do
    expect(rendered.css("button[type='submit'][disabled]")).to be_empty
  end

  context "when metrics_count is 0" do
    it "shows an auto-generate info notice" do
      expect(rendered.text).to include("auto-generated with AI")
    end

    it "keeps the submit button enabled" do
      expect(rendered.css("button[type='submit'][disabled]")).to be_empty
    end
  end

  it "renders prompt version when prompt present" do
    expect(rendered.text).to include("v#{prompt.version}")
  end

  it "renders gracefully when prompt is nil" do
    rendered = render_inline(described_class.new(form: build_form(prompt_id: nil)))
    expect(rendered.text).to include("My Eval")
  end
end
