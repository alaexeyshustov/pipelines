require "rails_helper"

RSpec.describe LlmTestBackend do
  describe ".hosted_llm_request?" do
    it "is true for OpenRouter" do
      expect(described_class.hosted_llm_request?("https://openrouter.ai/api/v1/chat/completions")).to be(true)
    end

    it "is false for a local Ollama host" do
      expect(described_class.hosted_llm_request?("http://localhost:11434/v1/chat/completions")).to be(false)
    end
  end
end
