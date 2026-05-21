# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setting do
  describe "validations" do
    it "is valid with required attributes" do
      expect(build(:setting)).to be_valid
    end

    it_behaves_like "requires attribute", :key,   :setting
    it_behaves_like "requires attribute", :value, :setting

    it "enforces uniqueness of key" do
      create(:setting, key: "emails_agent_model", value: "gpt-5.4")
      duplicate = build(:setting, key: "emails_agent_model", value: "other-model")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).not_to be_empty
    end
  end

  describe ".fetch" do
    it "returns the stored value for a known key" do
      create(:setting, key: "emails_agent_model", value: "custom-model")
      expect(described_class.fetch("emails_agent_model")).to eq("custom-model")
    end

    it "returns nil when key is absent" do
      expect(described_class.fetch("emails_agent_model")).to be_nil
    end

    context "with a warm cache" do
      let(:cache) { ActiveSupport::Cache::MemoryStore.new }

      before { allow(Rails).to receive(:cache).and_return(cache) }

      it "returns the cached value without querying the database" do
        cache.write("setting/emails_agent_model", "cached-model")
        allow(described_class).to receive(:find_by)
        described_class.fetch("emails_agent_model")
        expect(described_class).not_to have_received(:find_by)
      end
    end
  end

  describe ".set" do
    it "creates a new setting" do
      described_class.set("emails_agent_model", "gpt-5.4")
      expect(described_class.fetch("emails_agent_model")).to eq("gpt-5.4")
    end

    it "updates an existing setting" do
      create(:setting, key: "emails_agent_model", value: "old-model")
      described_class.set("emails_agent_model", "new-model")
      expect(described_class.fetch("emails_agent_model")).to eq("new-model")
    end

    context "with write-through caching" do
      let(:cache) { ActiveSupport::Cache::MemoryStore.new }

      before { allow(Rails).to receive(:cache).and_return(cache) }

      it "writes the value into the cache after saving to the database" do
        described_class.set("emails_agent_model", "new-model")
        expect(cache.read("setting/emails_agent_model")).to eq("new-model")
      end

      it "subsequent fetch reads from cache without a DB query" do
        described_class.set("emails_agent_model", "cached-model")
        allow(described_class).to receive(:find_by)
        described_class.fetch("emails_agent_model")
        expect(described_class).not_to have_received(:find_by)
      end
    end
  end

  describe "KEYS" do
    it "lists the known LLM model setting keys" do
      expect(described_class::KEYS).to include(
        "emails_agent_model", "records_agent_model",
        "evaluation_llm_model", "judge_llm_model"
      )
    end
  end
end
