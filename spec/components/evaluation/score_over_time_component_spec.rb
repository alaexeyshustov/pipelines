
require "rails_helper"

RSpec.describe Evaluation::ScoreOverTimeComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:agent_name) { "EmailClassifierAgent" }

  context "with no experiments" do
    let(:component) { described_class.new(agent_name: agent_name, data: []) }

    it "renders no-data message" do
      expect(rendered.text).to include("No experiment data")
    end

    it "does not render a chart container" do
      expect(rendered.css("[data-controller='evaluation--score-chart']")).to be_empty
    end
  end

  context "with one experiment" do
    let(:data) { [ { id: 1, name: "exp_1", created_at: "2026-01-01", avg_score: 3.5 } ] }
    let(:component) { described_class.new(agent_name: agent_name, data: data) }

    it "renders chart container with stimulus controller" do
      expect(rendered.css("[data-controller='evaluation--score-chart']")).to be_present
    end

    it "embeds experiment data as JSON" do
      json = rendered.at_css("[data-controller='evaluation--score-chart']")
               &.attr("data-evaluation--score-chart-points-value")
      expect(JSON.parse(json).first["avg_score"]).to eq(3.5)
    end
  end

  context "with many experiments" do
    let(:data) do
      [
        { id: 1, name: "exp_1", created_at: "2026-01-01", avg_score: 3.0 },
        { id: 2, name: "exp_2", created_at: "2026-02-01", avg_score: 4.0 },
        { id: 3, name: "exp_3", created_at: "2026-03-01", avg_score: 4.5 }
      ]
    end
    let(:component) { described_class.new(agent_name: agent_name, data: data) }

    it "encodes all experiments in the JSON payload" do
      json = rendered.at_css("[data-controller='evaluation--score-chart']")
               &.attr("data-evaluation--score-chart-points-value")
      points = JSON.parse(json)
      expect(points.length).to eq(3)
      expect(points.pluck("avg_score")).to eq([ 3.0, 4.0, 4.5 ])
    end
  end
end
