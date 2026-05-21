# frozen_string_literal: true

require "rails_helper"

RSpec.describe LlmModels do
  def with_env(key, value)
    previous = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = previous
  end

  describe ".emails_agent" do
    it "defaults to mistral-large-latest" do
      with_env("EMAILS_AGENT_MODEL", nil) do
        expect(described_class.emails_agent).to eq("mistral-large-latest")
      end
    end

    it "reads from EMAILS_AGENT_MODEL" do
      with_env("EMAILS_AGENT_MODEL", "custom-model") do
        expect(described_class.emails_agent).to eq("custom-model")
      end
    end

    it "prefers Setting over ENV" do
      Setting.create!(key: "emails_agent_model", value: "db-model")
      with_env("EMAILS_AGENT_MODEL", "env-model") do
        expect(described_class.emails_agent).to eq("db-model")
      end
    end
  end

  describe ".records_agent" do
    it "defaults to gpt-5.1" do
      with_env("RECORDS_AGENT_MODEL", nil) do
        expect(described_class.records_agent).to eq("gpt-5.1")
      end
    end

    it "reads from RECORDS_AGENT_MODEL" do
      with_env("RECORDS_AGENT_MODEL", "gpt-4o") do
        expect(described_class.records_agent).to eq("gpt-4o")
      end
    end

    it "prefers Setting over ENV" do
      Setting.create!(key: "records_agent_model", value: "db-model")
      with_env("RECORDS_AGENT_MODEL", "env-model") do
        expect(described_class.records_agent).to eq("db-model")
      end
    end
  end

  describe ".evaluation" do
    it "defaults to gpt-5.4" do
      with_env("EVALUATION_LLM_MODEL", nil) do
        expect(described_class.evaluation).to eq("gpt-5.4")
      end
    end

    it "reads from EVALUATION_LLM_MODEL" do
      with_env("EVALUATION_LLM_MODEL", "gpt-4-turbo") do
        expect(described_class.evaluation).to eq("gpt-4-turbo")
      end
    end

    it "prefers Setting over ENV" do
      Setting.create!(key: "evaluation_llm_model", value: "db-model")
      with_env("EVALUATION_LLM_MODEL", "env-model") do
        expect(described_class.evaluation).to eq("db-model")
      end
    end
  end

  describe ".judge" do
    it "defaults to gpt-5.4" do
      with_env("JUDGE_LLM_MODEL", nil) do
        expect(described_class.judge).to eq("gpt-5.4")
      end
    end

    it "reads from JUDGE_LLM_MODEL" do
      with_env("JUDGE_LLM_MODEL", "claude-3-opus") do
        expect(described_class.judge).to eq("claude-3-opus")
      end
    end

    it "prefers Setting over ENV" do
      Setting.create!(key: "judge_llm_model", value: "db-model")
      with_env("JUDGE_LLM_MODEL", "env-model") do
        expect(described_class.judge).to eq("db-model")
      end
    end
  end
end
