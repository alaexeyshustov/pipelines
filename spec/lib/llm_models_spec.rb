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
    it "defaults to gpt-6-luna" do
      with_env("JUDGE_LLM_MODEL", nil) do
        expect(described_class.judge).to eq("gpt-6-luna")
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

  describe ".embedding" do
    it "defaults to qwen3-embedding:0.6b" do
      with_env("EMBEDDING_MODEL", nil) do
        expect(described_class.embedding).to eq("qwen3-embedding:0.6b")
      end
    end

    it "reads from EMBEDDING_MODEL" do
      with_env("EMBEDDING_MODEL", "bge-m3") do
        expect(described_class.embedding).to eq("bge-m3")
      end
    end

    it "prefers Setting over ENV" do
      Setting.create!(key: "embedding_model", value: "db-model")
      with_env("EMBEDDING_MODEL", "env-model") do
        expect(described_class.embedding).to eq("db-model")
      end
    end
  end

  describe ".evaluation_fallbacks" do
    it "defaults to a hosted model for a hosted evaluation model" do
      with_env("EVALUATION_FALLBACK_MODELS", nil) do
        with_env("EVALUATION_LLM_MODEL", "gpt-5.4") do
          expect(described_class.evaluation_fallbacks).to eq([ "mistral-large-latest" ])
        end
      end
    end

    it "defaults to none for a local evaluation model, so offline runs stay offline" do
      with_env("EVALUATION_FALLBACK_MODELS", nil) do
        with_env("EVALUATION_LLM_MODEL", "ollama/qwen3") do
          expect(described_class.evaluation_fallbacks).to eq([])
        end
      end
    end

    it "splits EVALUATION_FALLBACK_MODELS and drops blanks" do
      with_env("EVALUATION_FALLBACK_MODELS", "gpt-5.1, ,ollama/qwen3") do
        expect(described_class.evaluation_fallbacks).to eq([ "gpt-5.1", "ollama/qwen3" ])
      end
    end
  end

  it "has every ENV var it reads routed, blanked or local under LLM_TEST_BACKEND=ollama (spec/support/llm_test_backend.rb)" do
    read = []
    allow(ENV).to(receive(:fetch).and_wrap_original { |original, key, *args| (read << key) && original.call(key, *args) })
    described_class.singleton_methods(false).select { |name| described_class.method(name).arity.zero? }
      .each { |name| described_class.public_send(name) }

    expect(read.uniq).to match_array(LlmTestBackend::ROUTED_MODEL_VARS + LlmTestBackend::BLANKED_MODEL_VARS +
                                    LlmTestBackend::LOCAL_MODEL_VARS)
  end

  describe ".ref" do
    it "keeps a bare id unpinned" do
      ref = described_class.ref("gpt-5.4")
      expect(ref).to have_attributes(model: "gpt-5.4", provider: nil)
    end

    it "keeps hosted OpenRouter-style ids bare, so they still resolve through the registry" do
      expect([ "anthropic/claude-haiku-4.5", "openai/gpt-5.4", "mistral/mistral-large-latest" ].map { |id| described_class.ref(id) })
        .to all(have_attributes(provider: nil))
      expect(described_class.ref("anthropic/claude-haiku-4.5").model).to eq("anthropic/claude-haiku-4.5")
      expect(RubyLLM.models.find(described_class.ref("anthropic/claude-haiku-4.5").model).provider).to eq("openrouter")
    end

    it "pins a local provider" do
      expect([ described_class.ref("ollama/qwen3"), described_class.ref("gpustack/qwen3") ].map(&:provider))
        .to eq([ :ollama, :gpustack ])
    end

    it "keeps an Ollama tag in the model id" do
      expect(described_class.ref("ollama/qwen3:8b")).to have_attributes(model: "qwen3:8b", provider: :ollama)
    end

    it "splits on the first slash only" do
      expect(described_class.ref("ollama/hf.co/org/model").model).to eq("hf.co/org/model")
    end

    it "keeps an unknown prefix as part of a bare id" do
      expect(described_class.ref("meta-llama/llama-3")).to have_attributes(model: "meta-llama/llama-3", provider: nil)
    end

    it "treats a trailing slash or blank as a bare id" do
      expect(described_class.ref("ollama/")).to have_attributes(model: "ollama/", provider: nil)
      expect(described_class.ref(nil)).to have_attributes(model: "", provider: nil)
    end

    it "reports whether the provider is local" do
      expect([ described_class.ref("ollama/qwen3"), described_class.ref("openai/gpt-5.4"), described_class.ref("gpt-5.4") ]
        .map(&:local?)).to eq([ true, false, false ])
    end

    it "passes provider and assume_model_exists to RubyLLM.chat and Judge#judge" do
      expect(described_class.ref("ollama/qwen3").chat_options).to eq(model: "qwen3", provider: :ollama, assume_model_exists: true)
      expect(described_class.ref("gpt-5.4").chat_options).to eq(model: "gpt-5.4", provider: nil, assume_model_exists: false)
    end

    it "applies the model to an agent instance and declares it on an agent class" do
      agent_class = Class.new(RubyLLM::Agent)
      described_class.ref("ollama/qwen3").declare_on(agent_class)
      agent = described_class.ref("ollama/qwen3:8b").apply_to(agent_class.new)

      expect(agent_class.model).to include(model: "qwen3", provider: :ollama, assume_model_exists: true)
      expect(agent.chat.model).to have_attributes(id: "qwen3:8b", provider: "ollama")
    end

    it "builds a provider-pinned fallback target only when pinned" do
      expect(described_class.ref("gpt-5.1").fallback).to eq("gpt-5.1")
      expect(described_class.ref("ollama/qwen3").fallback)
        .to be_a(RubyLLM::Fallback).and have_attributes(id: "qwen3", provider: "ollama")
    end
  end
end
