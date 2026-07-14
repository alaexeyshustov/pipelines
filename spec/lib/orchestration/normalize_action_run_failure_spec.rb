require "rails_helper"

RSpec.describe Orchestration::NormalizeActionRunFailure do
  describe "#normalize" do
    let(:model) { "gpt-4.1-mini" }

    let(:action_run) do
      create(
        :orchestration_action_run,
        chat: create(:chat),
        agent_snapshot: {
          "model" => model,
          "prompt" => "Classify this email"
        }
      )
    end

    context "when the failure is a provider HTTP error" do
      let(:response) do
        Faraday::Response.new(
          status: 429,
          body: {
            "error" => {
              "message" => "Rate limit exceeded",
              "type" => "rate_limit"
            }
          }.to_json
        )
      end
      let(:error) { RubyLLM::RateLimitError.new(response, "An unknown error occurred") }

      it "extracts a concise summary and structured details" do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
        result = described_class.new(error:, action_run:, raw_content: nil).normalize

        expect(result.summary).to eq("openai API error (429): Rate limit exceeded")
        expect(result.details).to include(
          "category" => "provider_http_error",
          "provider" => "openai",
          "model" => "gpt-4.1-mini",
          "status_code" => 429,
          "message" => "Rate limit exceeded",
          "chat_id" => action_run.chat_id,
          "request_context" => {
            "agent_snapshot" => action_run.agent_snapshot
          }
        )
        expect(result.details["parsed_error"]).to eq(
          "message" => "Rate limit exceeded",
          "type" => "rate_limit"
        )
        expect(result.details["raw_response_excerpt"]).to include("rate_limit")
      end
    end

    context "when a provider HTTP error has a nested error.message (no top-level message)" do
      let(:response) do
        Data.define(:status, :body).new(
          status: 400,
          body: { "error" => { "code" => "invalid_input", "error" => { "message" => "Nested detail" } } }.to_json
        )
      end
      let(:error) { RubyLLM::BadRequestError.new(response, "An unknown error occurred") }

      it "digs into the nested error.message" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.summary).to include("Nested detail")
      end
    end

    context "when the provider HTTP response body is not valid JSON" do
      let(:response) { Data.define(:status, :body).new(status: 503, body: "Service Unavailable") }
      let(:error) { RubyLLM::ServiceUnavailableError.new(response, "unavailable") }

      it "returns nil parsed_error and falls back to the error message" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.details["parsed_error"]).to be_nil
        expect(result.summary).to include("unavailable")
      end
    end

    context "when the provider HTTP response body is a JSON array" do
      let(:response) { Data.define(:status, :body).new(status: 400, body: '["err1","err2"]') }
      let(:error) { RubyLLM::BadRequestError.new(response, "array errors") }

      it "preserves the array as parsed_error" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.details["parsed_error"]).to eq([ "err1", "err2" ])
      end
    end

    context "when the provider HTTP response has no message or error keys" do
      let(:response) { Data.define(:status, :body).new(status: 429, body: '{"code":42}') }
      let(:error) { RubyLLM::RateLimitError.new(response, "rate limited fallback") }

      it "falls back to the error message" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.summary).to include("rate limited fallback")
      end
    end

    context "when the parsed message is 'An unknown error occurred'" do
      let(:response) { Data.define(:status, :body).new(status: 500, body: '{"message":"An unknown error occurred"}') }
      let(:error) { RubyLLM::ServerError.new(response, "real server error") }

      it "skips the sentinel and falls back to the error message" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.summary).to include("real server error")
      end
    end

    context "when the agent_snapshot contains sensitive keys" do
      let(:action_run) do
        create(
          :orchestration_action_run,
          chat: create(:chat),
          agent_snapshot: { "model" => model, "api_key" => "sk-secret", "token" => "tok_abc" }
        )
      end
      let(:response) { Data.define(:status, :body).new(status: 429, body: '{"message":"Rate limit"}') }
      let(:error) { RubyLLM::RateLimitError.new(response, "Rate limit exceeded") }

      it "redacts sensitive keys in request_context.agent_snapshot" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        snapshot = result.details["request_context"]["agent_snapshot"]
        expect(snapshot["api_key"]).to eq("[REDACTED]")
        expect(snapshot["token"]).to eq("[REDACTED]")
        expect(snapshot["model"]).to eq("gpt-4.1-mini")
      end
    end

    context "when the agent_snapshot is blank" do
      let(:action_run) { create(:orchestration_action_run, chat: create(:chat), agent_snapshot: nil) }
      let(:response) { Data.define(:status, :body).new(status: 429, body: '{"message":"Rate limit"}') }
      let(:error) { RubyLLM::RateLimitError.new(response, "Rate limit exceeded") }

      it "returns nil request_context" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.details["request_context"]).to be_nil
      end
    end

    context "when the failure is a transport error" do
      let(:model) { "mistral-small-latest" }
      let(:error) { Faraday::TimeoutError.new("execution expired") }

      it "classifies it as a transport error" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize

        expect(result.summary).to eq("mistral transport error: execution expired")
        expect(result.details).to include(
          "category" => "transport_error",
          "provider" => "mistral",
          "model" => "mistral-small-latest",
          "message" => "execution expired",
          "status_code" => nil
        )
        expect(result.details["raw_response_excerpt"]).to be_nil
      end
    end

    context "when the failure is a Faraday::ConnectionFailed transport error" do
      let(:model) { "mistral-small-latest" }
      let(:error) { Faraday::ConnectionFailed.new("Connection refused - connect(2)") }

      it "classifies as transport_error" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.details["category"]).to eq("transport_error")
      end
    end

    context "when the failure is a Faraday::SSLError transport error" do
      let(:model) { "mistral-small-latest" }
      let(:error) { Faraday::SSLError.new("SSL_connect SYSCALL returned=5") }

      it "classifies as transport_error" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.details["category"]).to eq("transport_error")
      end
    end

    context "when the failure is invalid model output" do
      let(:model) { "claude-3-5-haiku-latest" }
      let(:error) do
        Orchestration::InvalidModelOutputError.new(
          "Invalid model output: data.result must be an array",
          raw_content: %({"email":"person@example.com","token":"super-secret-token-value"})
        )
      end

      it "sanitizes and truncates the raw excerpt" do # rubocop:disable RSpec/MultipleExpectations
        result = described_class.new(error:, action_run:, raw_content: nil).normalize

        expect(result.summary).to eq("Invalid model output: data.result must be an array")
        expect(result.details).to include(
          "category" => "invalid_model_output",
          "provider" => "anthropic",
          "model" => "claude-3-5-haiku-latest",
          "message" => "Invalid model output: data.result must be an array"
        )
        expect(result.details["raw_response_excerpt"]).to include("[REDACTED_EMAIL]")
        expect(result.details["raw_response_excerpt"]).to include("[REDACTED]")
      end
    end

    context "when invalid model output has a Hash as raw content (stringify path)" do
      let(:model) { "claude-3-5-haiku-latest" }
      let(:error) do
        Orchestration::InvalidModelOutputError.new(
          "Schema mismatch",
          raw_content: { "result" => [ 1, 2, 3 ], "count" => 3 }
        )
      end

      it "converts the hash to a JSON string for the excerpt" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.details["raw_response_excerpt"]).to include("result")
      end
    end

    context "when the failure is a generic (unclassified) error" do
      let(:model) { "mistral-small-latest" }
      let(:error) { RuntimeError.new("Something unexpected broke") }

      it "returns the sanitized message with nil details" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.summary).to eq("Something unexpected broke")
        expect(result.details).to be_nil
      end
    end

    context "when the error message contains a Bearer token" do
      let(:model) { "mistral-small-latest" }
      let(:error) { RuntimeError.new("Unauthorized: Bearer sk-abc123def456ghi") }

      it "redacts the Bearer token from the summary" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.summary).to include("[REDACTED]")
        expect(result.summary).not_to include("sk-abc123def456ghi")
      end
    end

    context "when the error message exceeds MAX_EXCERPT_LENGTH characters" do
      let(:model) { "mistral-small-latest" }
      let(:long_message) { "x" * (Orchestration::LogSanitizer::MAX_EXCERPT_LENGTH + 10) }
      let(:error) { RuntimeError.new(long_message) }

      it "truncates to MAX_EXCERPT_LENGTH and appends ellipsis" do
        result = described_class.new(error:, action_run:, raw_content: nil).normalize
        expect(result.summary).to end_with("...")
        expect(result.summary.length).to eq(Orchestration::LogSanitizer::MAX_EXCERPT_LENGTH + 3)
      end
    end
  end
end
