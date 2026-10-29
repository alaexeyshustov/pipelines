require "rails_helper"

RSpec.describe Evaluation::GradeDetailComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(result: result)) }

  let(:result) { build(:evaluation_evaluation_result, score: 0.75, passed: true, confidence: 0.82, raw: raw) }
  let(:raw) do
    { "type" => "score", "score" => 1.5, "levels" => [ "Wrong", "Partly right", "Fully right" ],
      "probabilities" => { "Wrong" => 0.05, "Partly right" => 0.55, "Fully right" => 0.4 } }
  end

  it "shows score, verdict and confidence" do
    expect(rendered.text).to include("75.0%", "passed", "confidence 82%")
  end

  it "shows the judged level and the probabilities" do
    expect(rendered.text).to include("level 2: Fully right", "Partly right 55%")
  end

  context "with a failed choice grade" do
    let(:result) { build(:evaluation_evaluation_result, score: 0.0, passed: false, confidence: nil, raw: { "type" => "choice", "choice" => "bad" }) }

    it "shows the chosen option and a failed badge" do
      expect(rendered.text).to include("bad", "failed", "0.0%")
    end
  end

  context "with a probability grade" do
    let(:result) { build(:evaluation_evaluation_result, score: 0.9, passed: nil, confidence: nil, raw: { "type" => "probability", "probability" => 0.9 }) }

    it "shows the likelihood and no verdict" do
      expect(rendered.text).to include("90% likely true")
      expect(rendered.text).not_to include("passed")
    end
  end

  context "without raw data" do
    let(:result) { build(:evaluation_evaluation_result, score: 0.5, passed: nil, confidence: nil, raw: nil) }

    it "still shows the score" do
      expect(rendered.text).to include("50.0%")
    end
  end
end
