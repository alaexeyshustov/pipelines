require "json"

module Orchestration
  class NormalizeActionRunFailure
    Result = Data.define(:summary, :details)

    def initialize(error:, action_run:, raw_content:)
      @error = error
      @action_run = action_run
      @raw_content = raw_content
    end

    def normalize
      return provider_http_error_result if provider_error_response.present?
      return transport_error_result if transport_error?
      return invalid_model_output_result if invalid_model_output?

      Result.new(summary: LogSanitizer.sanitize_string(@error.message.to_s), details: nil)
    end

    private

    def provider_error_response
      @provider_error_response ||= ProviderErrorResponse.new(error: @error)
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
      message = provider_error_response.message
      summary = "#{provider_display_name} API error (#{provider_error_response.status}): #{message}"

      Result.new(
        summary:,
        details: build_details(
          category: "provider_http_error",
          message:,
          status_code: provider_error_response.status,
          parsed_error: provider_error_response.parsed_error,
          raw_response_excerpt: sanitized_excerpt(provider_error_response.body)
        )
      )
    end

    def transport_error_result
      summary = "#{provider_display_name} transport error: #{LogSanitizer.sanitize_string(@error.message.to_s)}"

      Result.new(
        summary:,
        details: build_details(
          category: "transport_error",
          message: LogSanitizer.sanitize_string(@error.message.to_s),
          status_code: nil,
          parsed_error: nil,
          raw_response_excerpt: nil
        )
      )
    end

    def invalid_model_output_result
      summary = LogSanitizer.sanitize_string(@error.message.to_s)

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

      { "agent_snapshot" => LogSanitizer.sanitize_value(@action_run.agent_snapshot) }
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

      LogSanitizer.sanitize_string(LogSanitizer.stringify(value))
    end
  end
end
