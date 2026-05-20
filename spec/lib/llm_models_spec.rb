# frozen_string_literal: true

require "rails_helper"

RSpec.describe LlmModels do
  describe ".emails_agent" do
    it "defaults to mistral-large-latest" do
      expect(described_class.emails_agent).to eq("mistral-large-latest")
    end

    it "reads from EMAILS_AGENT_MODEL" do
      allow(ENV).to receive(:fetch).with("EMAILS_AGENT_MODEL", anything).and_return("custom-model")
      expect(described_class.emails_agent).to eq("custom-model")
    end
  end

  describe ".records_agent" do
    it "defaults to gpt-5.1" do
      expect(described_class.records_agent).to eq("gpt-5.1")
    end

    it "reads from RECORDS_AGENT_MODEL" do
      allow(ENV).to receive(:fetch).with("RECORDS_AGENT_MODEL", anything).and_return("gpt-4o")
      expect(described_class.records_agent).to eq("gpt-4o")
    end
  end

  describe ".evaluation" do
    it "defaults to gpt-5.4" do
      expect(described_class.evaluation).to eq("gpt-5.4")
    end

    it "reads from EVALUATION_LLM_MODEL" do
      allow(ENV).to receive(:fetch).with("EVALUATION_LLM_MODEL", anything).and_return("gpt-4-turbo")
      expect(described_class.evaluation).to eq("gpt-4-turbo")
    end
  end

  describe ".judge" do
    it "defaults to gpt-5.4" do
      expect(described_class.judge).to eq("gpt-5.4")
    end

    it "reads from JUDGE_LLM_MODEL" do
      allow(ENV).to receive(:fetch).with("JUDGE_LLM_MODEL", anything).and_return("claude-3-opus")
      expect(described_class.judge).to eq("claude-3-opus")
    end
  end
end
