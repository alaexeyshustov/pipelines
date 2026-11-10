require "net/http"
require "json"
require "uri"

# Opt-in live LLM mode: `LLM_TEST_BACKEND=ollama bundle exec rspec` runs only the `:llm`-tagged examples, against a
# local Ollama (OLLAMA_API_BASE, default http://localhost:11434/v1; OLLAMA_TEST_MODEL, default qwen3).
# Without the env var nothing changes: cassettes and stubs, no network.
#
# Decisions:
# - LlmModels.* are routed through ENV before the app loads (rails_helper calls .route_models!): agent classes
#   read LlmModels when they load, so a later stub would come too late. Evaluation fallbacks are forced blank
#   whatever the developer's env says, so a failing local call cannot reach a hosted fallback. The judge is
#   routed too, but Judge::ModelChoice still falls back to hosted jev-latest unless the registry lists the local
#   model as a `judgment` model; the tagged grader example skips then.
# - Only `:llm` examples run: the happy paths of agents, evaluation chats and the judge. Untagged LLM specs pin
#   hosted wire formats (Mistral/OpenAI request bodies) or stub failure responses (fallbacks, invalid output).
# - The Ollama host bypasses VCR and WebMock; a hosted LLM request raises instead of replaying a cassette.
#   Other cassettes (Gmail, GitHub) still replay.
# - An unreachable Ollama, a model that is not pulled, or one that rejects structured output (agents need it;
#   e.g. models on Ollama's MLX runner) skips the examples with the reason.
module LlmTestBackend
  # Every ENV var LlmModels reads; spec/lib/llm_models_spec.rb fails when they drift.
  ROUTED_MODEL_VARS = %w[EMAILS_AGENT_MODEL RECORDS_AGENT_MODEL EVALUATION_LLM_MODEL JUDGE_LLM_MODEL].freeze
  BLANKED_MODEL_VARS = %w[EVALUATION_FALLBACK_MODELS].freeze
  HOSTED_LLM_HOSTS = %w[api.openai.com api.mistral.ai api.anthropic.com generativelanguage.googleapis.com].freeze
  # Default mode never reaches a real Ollama: unstubbed requests to this host fail in WebMock.
  OFFLINE_API_BASE = "http://ollama.test/v1".freeze

  class << self
    def ollama? = ENV["LLM_TEST_BACKEND"] == "ollama"

    # True inside an `:llm` example that talks to a real Ollama; loosen assertions on model output then.
    def live? = ollama? && unavailable_reason.nil?

    def api_base = ollama? ? ENV.fetch("OLLAMA_API_BASE", "http://localhost:11434/v1") : OFFLINE_API_BASE

    def model_id = ENV.fetch("OLLAMA_TEST_MODEL", "qwen3")

    def model = "ollama/#{model_id}"

    # The model an `:llm` example should configure: the local one in ollama mode, else the recorded one.
    def model_for(recorded) = ollama? ? model : recorded

    # Where an `:llm` example's request goes, and the model id in its body: Ollama in ollama mode, else the stub.
    def completions_url_for(hosted) = ollama? ? "#{api_base.delete_suffix('/')}/chat/completions" : hosted

    def request_model_for(hosted) = ollama? ? model_id : hosted

    def host = URI(api_base).host

    def route_models!
      return unless ollama?

      ROUTED_MODEL_VARS.each { |var| ENV[var] = model }
      BLANKED_MODEL_VARS.each { |var| ENV[var] = "" }
    end

    def hosted_llm_request?(uri) = HOSTED_LLM_HOSTS.include?(URI(uri.to_s).host)

    def unavailable_reason
      return @unavailable_reason if defined?(@unavailable_reason)

      @unavailable_reason = probe
    end

    private

    def probe
      return "Ollama at #{api_base} has no model #{model_id} (ollama pull #{model_id})" unless pulled?

      structured_output_gap
    rescue StandardError => e
      "Ollama unreachable at #{api_base} (#{e.class}: #{e.message})"
    end

    def pulled?
      response = request(:get, "models")
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      ids = Array(JSON.parse(response.body)["data"]).pluck("id")
      ids.include?(model_id) || ids.include?("#{model_id}:latest")
    end

    def structured_output_gap
      schema = { type: "object", properties: { ok: { type: "boolean" } }, required: [ "ok" ] }
      response = request(:post, "chat/completions", model: model_id, max_tokens: 1,
                         messages: [ { role: "user", content: "ok?" } ],
                         response_format: { type: "json_schema", json_schema: { name: "probe", schema: } })
      "Ollama model #{model_id} rejects structured output (#{response.body.strip})" unless response.is_a?(Net::HTTPSuccess)
    end

    def request(verb, path, body = nil)
      uri = URI("#{api_base.delete_suffix('/')}/#{path}")
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 2, read_timeout: 120) do |http|
        next http.get(uri.request_uri) if verb == :get

        http.post(uri.request_uri, body.to_json, "Content-Type" => "application/json")
      end
    end
  end
end

RSpec.configure do |config|
  next unless LlmTestBackend.ollama?

  config.filter_run_including :llm

  config.before(:each, :llm) do
    reason = LlmTestBackend.unavailable_reason
    skip "LLM_TEST_BACKEND=ollama: #{reason}" if reason
  end
end
