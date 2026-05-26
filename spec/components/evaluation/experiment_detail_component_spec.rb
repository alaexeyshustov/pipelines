# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::ExperimentDetailComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(experiment: experiment)) }

  let(:experiment) { create(:evaluation_experiment) }

  it "renders the records evaluated count" do
    expect(rendered.text).to include("Records evaluated")
  end

  it "renders the Metrics section heading" do
    expect(rendered.text).to include("Metrics")
  end

  context "when metrics exist for the agent" do
    before { create(:evaluation_metric, agent_name: experiment.prompt.name, name: "Precision") }

    it "renders the metric name" do
      expect(rendered.text).to include("Precision")
    end
  end

  context "when dataset has samples" do
    before do
      create(:evaluation_dataset_sample, dataset: experiment.dataset, input: { "email" => "subject: Job offer from ACME" })
    end

    it "renders the Dataset Records section" do
      expect(rendered.text).to include("Dataset Records")
    end

    it "renders the record input data" do
      expect(rendered.text).to include("Job offer from ACME")
    end
  end

  context "when dataset has no samples" do
    it "does not render the Dataset Records section" do
      expect(rendered.text).not_to include("Dataset Records")
    end
  end

  context "when the prompt has system and user prompts" do
    before { experiment.prompt.update!(system_prompt: "You are an assistant", user_prompt: "Classify this email") }

    it "renders a collapsible Prompt section" do
      expect(rendered.css("details summary").map(&:text)).to include(match(/Prompt/))
    end

    it "renders the system prompt text" do
      expect(rendered.text).to include("You are an assistant")
    end
  end

  context "when the prompt has an output schema" do
    before { experiment.prompt.update!(output_schema: { "type" => "object", "properties" => { "label" => { "type" => "string" } } }) }

    it "renders a collapsible Output Schema section" do
      expect(rendered.css("details summary").map(&:text)).to include(match(/Output Schema/))
    end

    it "renders the schema as pretty JSON" do
      expect(rendered.text).to include('"type": "object"')
    end
  end

  context "when the prompt has no output schema" do
    it "does not render the Output Schema section" do
      expect(rendered.text).not_to include("Output Schema")
    end
  end

  context "when a newer experiment exists" do
    before do
      create(:evaluation_experiment, status: :pending, prompt: experiment.prompt)
    end

    it "shows the pending notification" do
      expect(rendered.text).to include("pending")
    end
  end
end
