require "rails_helper"

RSpec.describe Orchestration::NullPromptResolver do
  describe "#call" do
    it "returns nil for a String agent name" do
      expect(described_class.new.call("Orchestration::Agents::EmailsClassifier")).to be_nil
    end

    it "returns nil for nil input" do
      expect(described_class.new.call(nil)).to be_nil
    end
  end
end
