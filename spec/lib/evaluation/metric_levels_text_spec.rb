require "rails_helper"

RSpec.describe Evaluation::MetricLevelsText do
  let(:choice_levels) { { "good" => { "description" => "Fully correct", "value" => 1.0 }, "ok" => { "description" => "Fine", "value" => 0.5 } } }

  it "parses score levels one per line, ignoring blanks" do
    expect(described_class.parse(kind: "score", text: "Bad\n\n Good \n")).to eq([ "Bad", "Good" ])
  end

  it "parses choice options with value and description" do
    expect(described_class.parse(kind: "choice", text: "good | 1.0 | Fully correct\nok | 0.5 | Fine")).to eq(choice_levels)
  end

  it "keeps an unparseable choice value as nil" do
    expect(described_class.parse(kind: "choice", text: "x | ? | d")).to eq("x" => { "description" => "d", "value" => nil })
  end

  it "has no levels for probability" do
    expect(described_class.parse(kind: "probability", text: "ignored")).to be_nil
  end

  it "round-trips both kinds" do
    expect(described_class.parse(kind: "choice", text: described_class.dump(kind: "choice", levels: choice_levels))).to eq(choice_levels)
    expect(described_class.dump(kind: "score", levels: [ "a", "b" ])).to eq("a\nb")
    expect(described_class.dump(kind: "probability", levels: nil)).to eq("")
  end
end
