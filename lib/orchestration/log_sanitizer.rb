module Orchestration
  module LogSanitizer
    MAX_EXCERPT_LENGTH = 500
    REDACTED_VALUE = "[REDACTED]".freeze
    REDACTED_EMAIL = "[REDACTED_EMAIL]".freeze

    def self.sanitize_value(value)
      case value
      when Hash   then sanitize_hash(value)
      when Array  then value.map { |item| sanitize_value(item) }
      when String then sanitize_string(value.to_s)
      else value
      end
    end

    def self.sanitize_hash(value)
      result = {} # : json_object
      value.each do |key, nested_value|
        result[key.to_s] = sensitive_key?(key) ? REDACTED_VALUE : sanitize_value(nested_value)
      end
      result
    end

    def self.sensitive_key?(key)
      key.to_s.match?(/\A(api[_-]?key|authorization|token|secret|password)\z/i)
    end

    def self.sanitize_string(value)
      sanitized = value.dup
      sanitized.gsub!(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i, REDACTED_EMAIL)
      sanitized.gsub!(/("?(?:api[_-]?key|authorization|token|secret|password)"?\s*:\s*")([^"]+)(")/i, "\\1#{REDACTED_VALUE}\\3")
      sanitized.gsub!(/(Bearer\s+)[A-Za-z0-9\-._~+\/]+=*/i, "\\1#{REDACTED_VALUE}")
      truncate(sanitized)
    end

    def self.truncate(value)
      return value if value.length <= MAX_EXCERPT_LENGTH

      "#{value[0, MAX_EXCERPT_LENGTH]}..."
    end

    def self.stringify(value)
      JSON::Helpers.safe_generate(value)
    end
  end
end
