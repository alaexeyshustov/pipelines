module Orchestration
  class ModelOutputParser
    def parse(content, structured_output_expected:)
      return content.transform_keys(&:to_s) if content.is_a?(Hash)

      return parse_string(content, structured_output_expected) if content.is_a?(String)

      raise InvalidModelOutputError.new("Invalid model output: expected JSON object", raw_content: content) if structured_output_expected

      nil
    end

    def validate!(output, policy:, raw_content:)
      SchemaValidator.new(policy.output_schema).validate!(output)
    rescue SchemaValidator::Error => error
      raise error if policy.output_schema.blank?

      raise InvalidModelOutputError.new(error.message, raw_content: raw_content)
    end

    private

    def parse_string(content, structured_output_expected)
      parsed = JSON.parse(content)
      return parsed.transform_keys(&:to_s) if parsed.is_a?(Hash)

      raise InvalidModelOutputError.new("Invalid model output: expected JSON object", raw_content: parsed) if structured_output_expected

      nil
    rescue JSON::ParserError => error
      raise InvalidModelOutputError.new("Invalid model output: #{error.message}", raw_content: content) if structured_output_expected

      nil
    end
  end
end
