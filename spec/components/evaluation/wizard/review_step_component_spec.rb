# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Wizard::ReviewStepComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(
      agent_name: "Emails::ClassifyAgent",
      prompt: prompt,
      experiment_name: "My Eval",
      metrics_count: 4,
      dataset: dataset
    ))
  end

  let(:prompt)  { build(:orchestration_prompt, name: "classify_agent", version: 3) }
  let(:dataset) { build(:evaluation_dataset, name: "emails_dataset") }

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
    expect(rendered.text).to include("4")
  end

  it "renders a Run Experiment submit button" do
    expect(rendered.css("button[type='submit']").text).to include("Run")
  end

  it "enables the submit button when metrics are present" do
    expect(rendered.css("button[type='submit'][disabled]")).to be_empty
  end

  context "when metrics_count is 0" do
    subject(:rendered) do
      render_inline(described_class.new(
        agent_name: "Emails::ClassifyAgent",
        prompt: prompt,
        experiment_name: "My Eval",
        metrics_count: 0,
        dataset: dataset
      ))
    end

    it "shows an auto-generate info notice" do
      expect(rendered.text).to include("auto-generated with AI")
    end

    it "keeps the submit button enabled" do
      expect(rendered.css("button[type='submit'][disabled]")).to be_empty
    end
  end

  it "renders prompt version when prompt present" do
    expect(rendered.text).to include("v3")
  end

  it "renders gracefully when prompt is nil" do
    rendered = render_inline(described_class.new(
      agent_name: "Emails::ClassifyAgent",
      prompt: nil,
      experiment_name: "My Eval",
      metrics_count: 4,
      dataset: dataset
    ))
    expect(rendered.text).to include("My Eval")
  end
end
