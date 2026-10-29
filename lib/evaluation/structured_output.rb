module Evaluation
  # The payload of a RubyLLM response produced with a schema (Chat#with_schema / Agent schema DSL):
  # providers return it either already parsed (Hash) or as the JSON text the schema guaranteed.
  class StructuredOutput
    def self.from(message)
      content = message.content
      return content if content.is_a?(Hash)

      parsed = message.parsed
      raise ArgumentError, "Structured output is not an object" unless parsed.is_a?(Hash)

      parsed
    end
  end
end
