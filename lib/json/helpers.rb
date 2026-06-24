# frozen_string_literal: true

module JSON
  module Helpers
    def self.safe_parse(str, fallback: nil)
      return fallback unless str.is_a?(String)

      JSON.parse(str)
    rescue JSON::ParserError
      fallback
    end

    def self.safe_generate(value)
      return value.to_s if value.is_a?(String)

      JSON.generate(value).to_s
    rescue JSON::GeneratorError, TypeError
      value.to_s
    end
  end
end
