require "rails_helper"

RSpec.describe Email::SearchQuery do
  let!(:strong) { create(:email, subject: "Interview interview", body: "Interview schedule for next week") }
  let!(:weak) { create(:email, subject: "Hello", body: "Maybe an interview later, plus a long text " * 3) }

  before { create(:email, subject: "Newsletter", body: "Nothing relevant") }

  it "ranks better matches first" do
    expect(described_class.call("interview").map(&:email)).to eq([ strong, weak ])
  end

  it "returns snippets with highlight markers" do
    hit = described_class.call("schedule").first
    expect(hit.snippet).to include("[[schedule]]")
  end

  it "exposes a bm25 rank where lower is better" do
    first, second = described_class.call("interview")
    expect(first.rank).to be < second.rank
  end

  it "respects the limit" do
    expect(described_class.call("interview", limit: 1).size).to eq(1)
  end

  it "returns nothing for blank queries" do
    expect(described_class.call("  ")).to eq([])
    expect(described_class.call(nil)).to eq([])
  end

  it "does not raise on quotes and FTS operators" do
    [ %q("unbalanced), "foo AND", "NOT", "a OR (b", "x*", "col:val", "-", %q(it's) ].each do |q|
      expect { described_class.call(q) }.not_to raise_error
    end
  end

  it "treats operator words as plain terms" do
    create(:email, subject: "Offer and terms", body: "x")
    expect(described_class.call("offer AND terms").size).to eq(1)
  end
end
