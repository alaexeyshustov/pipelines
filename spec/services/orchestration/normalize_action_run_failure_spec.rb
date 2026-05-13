require "rails_helper"

RSpec.describe Orchestration::NormalizeActionRunFailure do
  describe ".call" do
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
      let(:model) { "gpt-4.1-mini" }
      let(:response) do
        instance_double(
          Faraday::Response,
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
        result = described_class.call(error:, action_run:, raw_content: nil)

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

    context "when the failure is a transport error" do
      let(:model) { "mistral-small-latest" }
      let(:error) { Faraday::TimeoutError.new("execution expired") }

      it "classifies it as a transport error" do
        result = described_class.call(error:, action_run:, raw_content: nil)

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

    context "when the failure is invalid model output" do
      let(:model) { "claude-3-5-haiku-latest" }
      let(:error) do
        Orchestration::InvalidModelOutputError.new(
          "Invalid model output: data.result must be an array",
          raw_content: %({"email":"person@example.com","token":"super-secret-token-value"})
        )
      end

      it "sanitizes and truncates the raw excerpt" do # rubocop:disable RSpec/MultipleExpectations
        result = described_class.call(error:, action_run:, raw_content: nil)

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
  end
end
