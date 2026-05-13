require "json"

module Orchestration
  class NormalizeActionRunFailure
    MAX_EXCERPT_LENGTH = 500
    REDACTED_VALUE = "[REDACTED]".freeze
    REDACTED_EMAIL = "[REDACTED_EMAIL]".freeze

    Result = Data.define(:summary, :details)
    class Result
      def initialize(summary:, details:) = super
    end

    def self.call(error:, action_run:, raw_content:)
      new(error:, action_run:, raw_content:).call
    end

    def initialize(error:, action_run:, raw_content:)
      @error = error
      @action_run = action_run
      @raw_content = raw_content
    end

    def call
      return provider_http_error_result if provider_http_error?
      return transport_error_result if transport_error?
      return invalid_model_output_result if invalid_model_output?

      Result.new(summary: sanitize_string(@error.message.to_s), details: nil)
    end

    private

    def provider_http_error?
      ruby_llm_error?(@error) && @error.respond_to?(:response) && @error.response.present?
    end

    def transport_error?
      @error.is_a?(Faraday::TimeoutError) ||
        @error.is_a?(Faraday::ConnectionFailed) ||
        @error.is_a?(Faraday::SSLError) ||
        @error.is_a?(Faraday::ParsingError)
    end

    def invalid_model_output?
      @error.is_a?(InvalidModelOutputError)
    end

    def provider_http_error_result
      parsed_error = extract_parsed_error(response_body)
      message = provider_error_message(parsed_error)
      summary = "#{provider_display_name} API error (#{response_status}): #{message}"

      Result.new(
        summary:,
        details: build_details(
          category: "provider_http_error",
          message:,
          status_code: response_status,
          parsed_error:,
          raw_response_excerpt: sanitized_excerpt(response_body)
        )
      )
    end

    def transport_error_result
      summary = "#{provider_display_name} transport error: #{sanitize_string(@error.message.to_s)}"

      Result.new(
        summary:,
        details: build_details(
          category: "transport_error",
          message: sanitize_string(@error.message.to_s),
          status_code: nil,
          parsed_error: nil,
          raw_response_excerpt: nil
        )
      )
    end

    def invalid_model_output_result
      summary = sanitize_string(@error.message.to_s)

      Result.new(
        summary:,
        details: build_details(
          category: "invalid_model_output",
          message: summary,
          status_code: nil,
          parsed_error: nil,
          raw_response_excerpt: sanitized_excerpt(invalid_model_raw_content)
        )
      )
    end

    def build_details(category:, message:, status_code:, parsed_error:, raw_response_excerpt:)
      {
        "category" => category,
        "provider" => provider_name,
        "model" => model_name,
        "status_code" => status_code,
        "message" => message,
        "parsed_error" => parsed_error,
        "raw_response_excerpt" => raw_response_excerpt,
        "chat_id" => @action_run.chat_id,
        "request_context" => request_context
      }
    end

    def request_context
      return nil if @action_run.agent_snapshot.blank?

      { "agent_snapshot" => sanitize_value(@action_run.agent_snapshot) }
    end

    def response
      @error.response
    end

    def response_status
      response.status
    end

    def response_body
      response.body
    end

    def provider_error_message(parsed_error)
      candidate =
        case parsed_error
        when Hash
          parsed_error["message"] || parsed_error.dig("error", "message")
        when String
          parsed_error
        end

      candidate = @error.message if candidate.blank? || candidate == "An unknown error occurred"
      candidate = response_body if candidate.blank? || candidate == "An unknown error occurred"
      sanitize_string(candidate.to_s)
    end

    def extract_parsed_error(body)
      parsed = parse_json(body)

      value =
        case parsed
        when Hash
          parsed["error"] || parsed
        when Array
          parsed
        end

      sanitize_value(value)
    end

    def parse_json(value)
      JSON.parse(value)
    rescue JSON::ParserError, TypeError
      nil
    end

    def invalid_model_raw_content
      @error.raw_content
    end

    def model_name
      @model_name ||= @action_run.agent_snapshot&.dig("model")
    end

    def provider_name
      @provider_name ||= begin
        return nil if model_name.blank?

        provider_class = Object.const_get(:RubyLLM).const_get(:Provider)
        provider_class.for(model_name)&.slug
      rescue StandardError
        nil
      end
    end

    def provider_display_name
      provider_name || "provider"
    end

    def sanitized_excerpt(value)
      return nil if value.blank?

      sanitize_string(stringify(value))
    end

    def stringify(value)
      value.is_a?(String) ? value : JSON.generate(value)
    rescue JSON::GeneratorError, TypeError
      value.to_s
    end

    def sanitize_value(value)
      case value
      when Hash
        result = {} # : Hash[String, untyped]
        value.each do |key, nested_value|
          result[key.to_s] =
            if sensitive_key?(key)
              REDACTED_VALUE
            else
              sanitize_value(nested_value)
            end
        end
        result
      when Array
        value.map { |item| sanitize_value(item) }
      when String
        sanitize_string(value)
      else
        value
      end
    end

    def ruby_llm_error?(error)
      error.class.ancestors.any? { |ancestor| ancestor.name == "RubyLLM::Error" }
    end

    def sensitive_key?(key)
      key.to_s.match?(/\A(api[_-]?key|authorization|token|secret|password)\z/i)
    end

    def sanitize_string(value)
      sanitized = value.dup
      sanitized.gsub!(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i, REDACTED_EMAIL)
      sanitized.gsub!(/("?(?:api[_-]?key|authorization|token|secret|password)"?\s*:\s*")([^"]+)(")/i, "\\1#{REDACTED_VALUE}\\3")
      sanitized.gsub!(/(Bearer\s+)[A-Za-z0-9\-._~+\/]+=*/i, "\\1#{REDACTED_VALUE}")
      truncate(sanitized)
    end

    def truncate(value)
      return value if value.length <= MAX_EXCERPT_LENGTH

      "#{value[0, MAX_EXCERPT_LENGTH]}..."
    end
  end
end
