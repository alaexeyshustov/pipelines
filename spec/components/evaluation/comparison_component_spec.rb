require "rails_helper"

RSpec.describe Evaluation::ComparisonComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:result) do
    Evaluation::Comparison::ComparisonResult.new(
      baseline_score: 0.6,
      candidate_score: 0.8,
      baseline_metrics: { "clarity" => 0.6, "accuracy" => 0.6 },
      candidate_metrics: { "clarity" => 0.9, "accuracy" => 0.7 },
      metric_deltas: { "clarity" => 0.3, "accuracy" => 0.1 },
      overall_delta: 0.2
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
    expect(rendered.text).to include("60%")
    expect(rendered.text).to include("80%")
  end

  it "renders overall delta" do
    expect(rendered.text).to include("+20.0 pts")
  end

  it "renders per-metric deltas" do
    expect(rendered.text).to include("+30.0 pts")
    expect(rendered.text).to include("+10.0 pts")
  end

  it "applies green class for positive deltas" do
    expect(rendered.css(".text-green-600")).to be_present
  end

  context "with negative delta" do
    let(:result) do
      Evaluation::Comparison::ComparisonResult.new(
        baseline_score: 0.8,
        candidate_score: 0.6,
        baseline_metrics: { "clarity" => 0.8 },
        candidate_metrics: { "clarity" => 0.6 },
        metric_deltas: { "clarity" => -0.2 },
        overall_delta: -0.2
      )
    end

    it "applies red class for negative deltas" do
      expect(rendered.css(".text-red-600")).to be_present
    end

    it "formats negative delta with minus sign" do
      expect(rendered.text).to include("-20.0 pts")
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
