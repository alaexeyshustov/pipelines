# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::ComparisonComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:result) do
    Evaluation::Comparison::ComparisonResult.new(
      baseline_score: 3.0,
      candidate_score: 4.0,
      baseline_metrics: { "clarity" => 3.0, "accuracy" => 3.0 },
      candidate_metrics: { "clarity" => 4.5, "accuracy" => 3.5 },
      metric_deltas: { "clarity" => 1.5, "accuracy" => 0.5 },
      overall_delta: 1.0
    )
  end

  let(:baseline) { build(:evaluation_experiment, name: "baseline") }
  let(:candidate) { build(:evaluation_experiment, name: "candidate") }
  let(:component) { described_class.new(result: result, baseline_experiment: baseline, candidate_experiment: candidate) }

  it "renders metric names" do
    expect(rendered.text).to include("clarity")
    expect(rendered.text).to include("accuracy")
  end

  it "renders baseline and candidate scores" do
    expect(rendered.text).to include("3.0")
    expect(rendered.text).to include("4.0")
  end

  it "renders overall delta" do
    expect(rendered.text).to include("+1.0")
  end

  it "renders per-metric deltas" do
    expect(rendered.text).to include("+1.5")
    expect(rendered.text).to include("+0.5")
  end

  it "applies green class for positive deltas" do
    expect(rendered.css(".text-green-600")).to be_present
  end

  context "with negative delta" do
    let(:result) do
      Evaluation::Comparison::ComparisonResult.new(
        baseline_score: 4.0,
        candidate_score: 3.0,
        baseline_metrics: { "clarity" => 4.0 },
        candidate_metrics: { "clarity" => 3.0 },
        metric_deltas: { "clarity" => -1.0 },
        overall_delta: -1.0
      )
    end

    it "applies red class for negative deltas" do
      expect(rendered.css(".text-red-600")).to be_present
    end

    it "formats negative delta with minus sign" do
      expect(rendered.text).to include("-1.0")
    end
  end

  context "with nil score" do
    let(:result) do
      Evaluation::Comparison::ComparisonResult.new(
        baseline_score: nil,
        candidate_score: nil,
        baseline_metrics: {},
        candidate_metrics: {},
        metric_deltas: {},
        overall_delta: nil
      )
    end

    it "renders em dash for nil scores" do
      expect(rendered.text).to include("—")
    end
  end
end
