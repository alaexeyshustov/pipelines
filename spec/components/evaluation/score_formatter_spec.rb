require "rails_helper"

RSpec.describe Evaluation::ScoreFormatter do
  it "formats fractions as percentages" do
    expect(described_class.percent(0.875)).to eq("88%")
    expect(described_class.percent(0.875, digits: 1)).to eq("87.5%")
    expect(described_class.percent(nil)).to eq("—")
  end

  it "formats deltas as percentage points" do
    expect(described_class.points(0.05)).to eq("+5.0 pts")
    expect(described_class.points(-0.125)).to eq("-12.5 pts")
    expect(described_class.points(nil)).to eq("—")
  end

  it "formats cost and token counts" do
    expect(described_class.cost(BigDecimal("0.5"))).to eq("$0.5000")
    expect(described_class.tokens(1_234_567)).to eq("1,234,567")
  end
end
