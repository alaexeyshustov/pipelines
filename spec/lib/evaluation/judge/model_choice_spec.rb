require "rails_helper"

RSpec.describe Evaluation::Judge::ModelChoice do
  it "keeps a judgment-capable model" do
    expect(described_class.call("gpt-6-luna")).to eq("gpt-6-luna")
  end

  it "falls back to LlmModels.judge for a plain chat model" do
    expect(described_class.call("gpt-5.4")).to eq(LlmModels.judge)
  end

  it "falls back for an unknown model id" do
    expect(described_class.call("no-such-model")).to eq(LlmModels.judge)
  end

  it "uses LlmModels.judge when nothing is preferred" do
    expect(described_class.call(nil)).to eq(LlmModels.judge)
  end

  it "defaults the judge to gpt-6-luna" do
    expect(LlmModels.judge).to eq("gpt-6-luna")
  end
end
