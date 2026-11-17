require "rails_helper"

RSpec.describe Evaluation::ActivePromptResolver do
  describe "#call" do
    context "when a prompt exists for the agent" do
      it "returns the latest version's system_prompt" do
        create(:orchestration_prompt, name: "Agent::A", system_prompt: "v1", version: 1)
        create(:orchestration_prompt, name: "Agent::A", system_prompt: "v2", version: 2)

        expect(described_class.new.call("Agent::A")).to eq("v2")
      end
    end

    context "when no prompt exists for the agent" do
      it "returns nil" do
        expect(described_class.new.call("Agent::Missing")).to be_nil
      end
    end

    it "queries Evaluation::Prompt.last_for_agent only once per distinct agent, returning the cached value each time" do
      create(:orchestration_prompt, name: "Agent::A", system_prompt: "hello")
      resolver = described_class.new

      allow(Evaluation::Prompt).to receive(:last_for_agent).and_call_original

      3.times { expect(resolver.call("Agent::A")).to eq("hello") }

      expect(Evaluation::Prompt).to have_received(:last_for_agent).with("Agent::A").once
    end

    it "memoizes nil results, querying only once for an agent with no prompt" do
      resolver = described_class.new

      allow(Evaluation::Prompt).to receive(:last_for_agent).and_call_original

      3.times { expect(resolver.call("Agent::Missing")).to be_nil }

      expect(Evaluation::Prompt).to have_received(:last_for_agent).with("Agent::Missing").once
    end
  end
end
