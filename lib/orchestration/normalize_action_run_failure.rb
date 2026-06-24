require "json"

module Orchestration
  # rubocop:disable Metrics/ClassLength
  class NormalizeActionRunFailure
    MAX_EXCERPT_LENGTH = 500
    REDACTED_VALUE = "[REDACTED]".freeze
    REDACTED_EMAIL = "[REDACTED_EMAIL]".freeze

    Result = Data.define(:summary, :details)

    def initialize(error:, action_run:, raw_content:)
      @error = error
      @action_run = action_run
      @raw_content = raw_content
    end

    def normalize
      return provider_http_error_result if provider_http_error?
      return transport_error_result if transport_error?
      return invalid_model_output_result if invalid_model_output?

      Result.new(summary: sanitize_string(@error.message.to_s), details: nil)
    end

    private

    def provider_http_error?
      response_candidate ? true : false
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
      candidate = response_candidate
      raise ArgumentError, "RubyLLM error response unavailable" unless candidate

      candidate
    end

    def response_status
      response.status
    end

    def response_body
      response.body
    end

    def provider_error_message(parsed_error)
      candidate = extract_candidate_message(parsed_error)
      candidate = fallback_if_unknown(candidate, @error.message)
      candidate = fallback_if_unknown(candidate, response_body)
      sanitize_string(candidate.to_s)
    end

    def extract_candidate_message(parsed_error)
      case parsed_error
      when Hash   then parsed_error["message"] || parsed_error.dig("error", "message")
      when String then parsed_error
      end # : String?
    end

    def fallback_if_unknown(candidate, fallback)
      candidate.blank? || candidate == "An unknown error occurred" ? fallback : candidate
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
      return nil unless value.is_a?(String)

      JSON.parse(value)
    rescue JSON::ParserError
      nil
    end

    def invalid_model_raw_content
      error = @error
      if error.is_a?(InvalidModelOutputError)
        error.raw_content
      else
        @raw_content
      end
    end

    def model_name
      @model_name ||= @action_run.agent_snapshot&.dig("model")
    end

    def provider_name
      @provider_name ||= begin
        RubyLLM::Provider.for(model_name)&.slug if model_name.present?
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
      return value.to_s if value.is_a?(String)

      JSON.generate(value).to_s
    rescue JSON::GeneratorError, TypeError
      value.to_s
    end

    def sanitize_value(value)
      case value
      when Hash   then sanitize_hash(value)
      when Array  then value.map { |item| sanitize_value(item) }
      when String then sanitize_string(value.to_s)
      else value
      end
    end

    def sanitize_hash(value)
      result = {} # : json_object
      value.each do |key, nested_value|
        result[key.to_s] = sensitive_key?(key) ? REDACTED_VALUE : sanitize_value(nested_value)
      end
      result
    end

    def response_candidate
      return nil unless ruby_llm_error?(@error)
      return nil unless @error.respond_to?(:response)

      ruby_llm_err = @error #: RubyLLM::Error
      candidate = ruby_llm_err.response #: _Response?
      return nil unless candidate

      candidate
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
  # rubocop:enable Metrics/ClassLength
end
