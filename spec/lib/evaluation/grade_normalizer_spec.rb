require "rails_helper"

RSpec.describe Evaluation::GradeNormalizer do
  subject(:normalized) { described_class.call(value: value, metric: metric) }

  let(:metric) { build(:evaluation_metric) }

  def score_answer(score, levels: %w[bad ok good])
    RubyLLM::Score.new(score: score, levels: levels, probabilities: { 0 => 0.1, 1 => 0.2, 2 => 0.7 }, confidence: 0.9)
  end

  context "with a Probability" do
    let(:value) { RubyLLM::Probability.new(probability: 0.73) }

    it { is_expected.to eq(0.73) }
  end

  context "with a Score" do
    let(:metric) { build(:evaluation_metric, :score) }

    it "maps the lowest level to 0.0" do
      expect(described_class.call(value: score_answer(0.0), metric: metric)).to eq(0.0)
    end

    it "maps the top level to 1.0" do
      expect(described_class.call(value: score_answer(2.0), metric: metric)).to eq(1.0)
    end

    it "scales fractional scores by levels - 1" do
      expect(described_class.call(value: score_answer(1.5), metric: metric)).to eq(0.75)
    end

    it "works for any number of levels" do
      value = score_answer(3.0, levels: %w[a b c d e])
      expect(described_class.call(value: value, metric: metric)).to eq(0.75)
    end

    it "clamps out-of-range scores" do
      expect(described_class.call(value: score_answer(2.4), metric: metric)).to eq(1.0)
    end

    it "returns nil for a single level (no scale)" do
      expect(described_class.call(value: score_answer(0.0, levels: %w[only]), metric: metric)).to be_nil
    end
  end

  context "with a Choice" do
    let(:metric) { build(:evaluation_metric, :choice) }
    let(:value) do
      RubyLLM::Choice.new(choice: "good", probabilities: { "good" => 0.6, "ok" => 0.3, "bad" => 0.1 }, confidence: 0.8)
    end

    it "is the probability-weighted sum of option values" do
      expect(normalized).to be_within(1e-9).of(0.75)
    end

    it "supports a single pass option when values are omitted" do
      metric = build(:evaluation_metric, kind: "choice",
                     levels: { "pass" => { "description" => "ok", "pass" => true }, "fail" => { "description" => "no" } })
      value = RubyLLM::Choice.new(choice: "pass", probabilities: { "pass" => 0.8, "fail" => 0.2 }, confidence: 1.0)
      expect(described_class.call(value: value, metric: metric)).to eq(0.8)
    end

    it "returns nil when an option is not declared on the metric" do
      value = RubyLLM::Choice.new(choice: "other", probabilities: { "other" => 1.0 }, confidence: 1.0)
      expect(described_class.call(value: value, metric: metric)).to be_nil
    end

    it "returns nil when the metric has no options" do
      expect(described_class.call(value: value, metric: build(:evaluation_metric))).to be_nil
    end
  end

  context "with reviewer booleans" do
    it "maps true to 1.0" do
      expect(described_class.call(value: true, metric: metric)).to eq(1.0)
    end

    it "maps false to 0.0" do
      expect(described_class.call(value: false, metric: metric)).to eq(0.0)
    end

    it "excludes unknown (nil)" do
      expect(described_class.call(value: nil, metric: metric)).to be_nil
    end
  end

  context "with a non-finite probability" do
    let(:value) { RubyLLM::Probability.new(probability: Float::NAN) }

    it { is_expected.to be_nil }
  end
end
