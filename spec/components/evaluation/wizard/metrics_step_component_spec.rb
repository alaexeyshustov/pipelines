# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Wizard::MetricsStepComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(form: build_form)) }

  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:metrics)    { create_list(:evaluation_metric, 2, agent_name: agent_name) }

  def build_form(overrides = {})
    payload = { "agent_name" => overrides.fetch(:agent_name, agent_name) }
    Evaluation::Wizard::Step2Form.new(draft_payload: payload)
  end

  it "renders metric names" do
    metrics.each { |m| expect(rendered.text).to include(m.name) }
  end

  it "renders a Generate with AI button" do
    expect(rendered.text).to include("Generate")
  end

  it "renders a form for adding a metric pointing to evaluation_metrics_path" do
    expect(rendered.css("form[action*='metrics']")).to be_present
  end

  it "renders a Next button to advance the wizard" do
    expect(rendered.css("form[action*='/evaluation/experiments'] button[type='submit']").text).to include("Next")
  end

  it "renders empty state when no metrics exist" do
    expect(rendered.text).to include("No metrics")
  end
end
