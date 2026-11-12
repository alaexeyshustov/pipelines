require "rails_helper"

# A chat against a local model addressed as "ollama/<model>" (LlmModels.ref -> provider: :ollama).
# Default mode stubs the Ollama endpoint; LLM_TEST_BACKEND=ollama sends the requests to the local model
# (spec/support/llm_test_backend.rb), so output assertions only check the shape then.
RSpec.describe "Ollama chat round-trip", :llm, type: :integration do # rubocop:disable RSpec/DescribeClass
  let(:ref) { LlmModels.ref(LlmTestBackend.model) }
  let(:completions_url) { "#{RubyLLM.config.ollama_api_base}/chat/completions" }

  before do
    next if LlmTestBackend.live?

    stub_request(:post, completions_url).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: {
        id: "chatcmpl-1", object: "chat.completion", model: LlmTestBackend.model_id,
        choices: [ { index: 0, message: { role: "assistant", content: '{"answer":"pong"}' }, finish_reason: "stop" } ],
        usage: { prompt_tokens: 12, completion_tokens: 4, total_tokens: 16 }
      }.to_json
    )
  end

  it "answers a plain chat on the pinned provider without a registry entry" do
    chat = RubyLLM.chat(model: ref.model, provider: ref.provider, assume_model_exists: ref.local?)
    response = chat.ask("Reply with the single word pong.")

    expect(chat.model).to have_attributes(id: LlmTestBackend.model_id, provider: "ollama")
    expect(response.content).to be_present
  end

  it "sends the bare model id to Ollama" do
    skip "asserts the stubbed request" if LlmTestBackend.live?

    RubyLLM.chat(model: ref.model, provider: ref.provider).ask("ping")

    expect(a_request(:post, completions_url).with { |req| JSON.parse(req.body)["model"] == "qwen3" }).to have_been_made
  end

  context "with a persisted runtime agent" do
    let(:experiment) { create(:evaluation_experiment) }
    let(:policy) do
      Orchestration::AgentResolutionPolicy::Result.new(
        model: LlmTestBackend.model, prompt: "Answer the question as JSON.", tools: [],
        output_schema: {
          "type" => "object", "additionalProperties" => false, "required" => [ "answer" ],
          "properties" => { "answer" => { "type" => "string" } }
        }
      )
    end

    it "returns structured output and records unpriced usage" do
      agent = Orchestration::RuntimeAgentBuilder.new(policy:).build
      output = Evaluation::UsageScope.call(experiment) { Evaluation::StructuredOutput.from(agent.ask("Say pong.")) }

      expect(agent.chat.reload.model).to have_attributes(model_id: LlmTestBackend.model_id, provider: "ollama")
      expect(output["answer"]).to(LlmTestBackend.live? ? be_a(String) : eq("pong"))
      expect(Evaluation::ExperimentUsageQuery.call(experiment_ids: [ experiment.id ])[experiment.id])
        .to have_attributes(calls: 1, cost: 0, total_tokens: be_positive)
    end
  end
end
