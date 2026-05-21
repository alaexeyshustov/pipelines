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
