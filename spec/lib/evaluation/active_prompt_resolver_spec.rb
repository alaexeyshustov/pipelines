require "rails_helper"

RSpec.describe Evaluation::ActivePromptResolver do
  def count_prompt_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 if payload[:sql].include?("evaluation_prompts") && payload[:name] != "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    count
  end

  describe "#call" do
    it "returns the active version's system_prompt" do
      create(:orchestration_prompt, name: "Agent::A", system_prompt: "v1", version: 1)
      create(:orchestration_prompt, :active, name: "Agent::A", system_prompt: "v2", version: 2)

      expect(described_class.new.call("Agent::A")).to eq("v2")
    end

    it "ignores a newer inactive version" do
      create(:orchestration_prompt, :active, name: "Agent::A", system_prompt: "live", version: 1)
      create(:orchestration_prompt, name: "Agent::A", system_prompt: "draft", version: 2)

      expect(described_class.new.call("Agent::A")).to eq("live")
    end

    it "returns nil when no version is active" do
      create(:orchestration_prompt, name: "Agent::A", system_prompt: "draft", version: 1)

      expect(described_class.new.call("Agent::A")).to be_nil
    end

    it "returns nil when no prompt exists for the agent" do
      expect(described_class.new.call("Agent::Missing")).to be_nil
    end

    it "queries once per distinct agent, returning the cached value each time" do
      create(:orchestration_prompt, :active, name: "Agent::A", system_prompt: "hello")
      resolver = described_class.new

      queries = count_prompt_queries { 3.times { expect(resolver.call("Agent::A")).to eq("hello") } }

      expect(queries).to eq(1)
    end

    it "memoizes nil results, querying only once for an agent with no active prompt" do
      create(:orchestration_prompt, name: "Agent::A", system_prompt: "draft")
      resolver = described_class.new

      queries = count_prompt_queries { 3.times { expect(resolver.call("Agent::A")).to be_nil } }

      expect(queries).to eq(1)
    end

    it "does not carry a cache across instances" do
      prompt = create(:orchestration_prompt, :active, name: "Agent::A", system_prompt: "old")
      expect(described_class.new.call("Agent::A")).to eq("old")

      prompt.update!(system_prompt: "new")

      expect(described_class.new.call("Agent::A")).to eq("new")
    end
  end
end
