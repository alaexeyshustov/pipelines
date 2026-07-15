module Orchestration
  class ProviderErrorResponse
    def initialize(error:)
      @error = error
    end

    def present?
      response_candidate ? true : false
    end

    def status
      response.status
    end

    def body
      response.body
    end

    def parsed_error
      extract_parsed_error(body)
    end

    def message
      provider_error_message(parsed_error)
    end

    private

    def response
      candidate = response_candidate
      raise ArgumentError, "RubyLLM error response unavailable" unless candidate

      candidate
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

    def provider_error_message(parsed_error)
      candidate = extract_candidate_message(parsed_error)
      candidate = fallback_if_unknown(candidate, @error.message)
      candidate = fallback_if_unknown(candidate, body)
      LogSanitizer.sanitize_string(candidate.to_s)
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

      LogSanitizer.sanitize_value(value)
    end

    def parse_json(value)
      JSON::Helpers.safe_parse(value)
    end
  end
end
