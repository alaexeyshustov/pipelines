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

  context "when a newer experiment exists" do
    before do
      create(:evaluation_experiment, status: :pending, prompt: experiment.prompt)
    end

    it "shows the pending notification" do
      expect(rendered.text).to include("pending")
    end
  end
end
