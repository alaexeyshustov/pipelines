require "rails_helper"

RSpec.describe Orchestration::ProviderErrorResponse do
  describe "#present?" do
    it "is true for a RubyLLM error with a response" do
      response = Data.define(:status, :body).new(status: 429, body: "{}")
      error = RubyLLM::RateLimitError.new(response, "rate limited")

      expect(described_class.new(error: error).present?).to be(true)
    end

    it "is false for a non-RubyLLM error" do
      expect(described_class.new(error: RuntimeError.new("boom")).present?).to be(false)
    end

    it "is false for a transport error" do
      expect(described_class.new(error: Faraday::TimeoutError.new("timeout")).present?).to be(false)
    end
  end

  describe "#status, #body, #parsed_error, #message" do
    it "extracts status, body, parsed error, and a sanitized top-level message" do # rubocop:disable RSpec/ExampleLength
      response = Data.define(:status, :body).new(
        status: 429,
        body: { "error" => { "message" => "Rate limit exceeded" } }.to_json
      )
      error = RubyLLM::RateLimitError.new(response, "An unknown error occurred")
      subject = described_class.new(error: error)

      aggregate_failures do
        expect(subject.status).to eq(429)
        expect(subject.body).to eq(response.body)
        expect(subject.parsed_error).to eq("message" => "Rate limit exceeded")
        expect(subject.message).to eq("Rate limit exceeded")
      end
    end

    it "digs into a nested error.message when there is no top-level message" do
      response = Data.define(:status, :body).new(
        status: 400,
        body: { "error" => { "code" => "invalid_input", "error" => { "message" => "Nested detail" } } }.to_json
      )
      error = RubyLLM::BadRequestError.new(response, "An unknown error occurred")

      expect(described_class.new(error: error).message).to eq("Nested detail")
    end

    it "falls back to the error's own message when the body is not valid JSON" do
      response = Data.define(:status, :body).new(status: 503, body: "Service Unavailable")
      error = RubyLLM::ServiceUnavailableError.new(response, "unavailable")
      subject = described_class.new(error: error)

      expect(subject.parsed_error).to be_nil
      expect(subject.message).to eq("unavailable")
    end

    it "preserves a JSON array body as parsed_error" do
      response = Data.define(:status, :body).new(status: 400, body: '["err1","err2"]')
      error = RubyLLM::BadRequestError.new(response, "array errors")

      expect(described_class.new(error: error).parsed_error).to eq([ "err1", "err2" ])
    end

    it "falls back to the error message when parsed error has no message or error key" do
      response = Data.define(:status, :body).new(status: 429, body: '{"code":42}')
      error = RubyLLM::RateLimitError.new(response, "rate limited fallback")

      expect(described_class.new(error: error).message).to eq("rate limited fallback")
    end

    it "skips the 'An unknown error occurred' sentinel and falls back to the error message" do
      response = Data.define(:status, :body).new(status: 500, body: '{"message":"An unknown error occurred"}')
      error = RubyLLM::ServerError.new(response, "real server error")

      expect(described_class.new(error: error).message).to eq("real server error")
    end

    it "sanitizes sensitive content in the extracted message" do
      response = Data.define(:status, :body).new(
        status: 400,
        body: { "message" => "Bearer sk-abc123def456ghi789" }.to_json
      )
      error = RubyLLM::BadRequestError.new(response, "An unknown error occurred")

      expect(described_class.new(error: error).message).to eq("Bearer [REDACTED]")
    end
  end
end
