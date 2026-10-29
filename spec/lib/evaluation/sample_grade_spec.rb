require "rails_helper"

RSpec.describe Evaluation::SampleGrade do
  def grade(name, score)
    Evaluation::Grade.new(metric_name: name, score: score, raw: {}, confidence: nil, passed: nil,
                          justification: "j", tokens: nil, cost: nil)
  end

  let(:accuracy) { build(:evaluation_metric, name: "accuracy", weight: 3.0) }
  let(:tone) { build(:evaluation_metric, name: "tone", weight: 1.0) }

  it "is the weighted mean of metric grades" do
    result = described_class.call(grades: [ grade("accuracy", 1.0), grade("tone", 0.0) ], metrics: [ accuracy, tone ])
    expect(result).to eq(0.75)
  end

  it "excludes unknown grades" do
    result = described_class.call(grades: [ grade("accuracy", 0.5), grade("tone", nil) ], metrics: [ accuracy, tone ])
    expect(result).to eq(0.5)
  end

  it "ignores grades without a metric and zero-weight metrics" do
    muted = build(:evaluation_metric, name: "muted", weight: 0.0)
    result = described_class.call(grades: [ grade("accuracy", 0.4), grade("muted", 1.0), grade("gone", 1.0) ],
                                  metrics: [ accuracy, muted ])
    expect(result).to be_within(1e-9).of(0.4)
  end

  it "returns nil when nothing is gradeable" do
    expect(described_class.call(grades: [ grade("tone", nil) ], metrics: [ tone ])).to be_nil
    expect(described_class.call(grades: [], metrics: [])).to be_nil
  end
end
