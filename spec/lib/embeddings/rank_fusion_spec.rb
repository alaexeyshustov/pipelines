require "rails_helper"

RSpec.describe Embeddings::RankFusion do
  it "scores 1 / (k + rank) per list, so items found by several lists win" do
    fused = described_class.call([ 1, 2, 3 ], [ 3, 4 ], k: 60)

    expect(fused.map(&:first)).to eq([ 3, 1, 2, 4 ])
    expect(fused.first.last).to be_within(1e-9).of((1.0 / 63) + (1.0 / 61))
    expect(fused.last.last).to be_within(1e-9).of(1.0 / 62)
  end

  it "keeps first-seen order for equal scores" do
    expect(described_class.call([ 1 ], [ 2 ]).map(&:first)).to eq([ 1, 2 ])
  end

  it "is empty without rankings" do
    expect(described_class.call([], [])).to eq([])
  end
end
