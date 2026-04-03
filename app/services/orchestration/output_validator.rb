module Orchestration
  class OutputValidator
    Error = Class.new(StandardError)

    def initialize(schema)
      @schema = schema
    end

    def validate!(output)
      return if @schema.nil?

      validate_node!(output, @schema, "output")
    end

    private

    def validate_node!(value, schema, path)
      case schema["type"]
      when "object"
        raise Error, "#{path} must be an object" unless value.is_a?(Hash)

        (schema["required"] || []).each do |key|
          raise Error, "#{path} missing required key: #{key}" unless value.key?(key)
        end

        (schema["properties"] || {}).each do |key, sub_schema|
          validate_node!(value[key], sub_schema, "#{path}.#{key}") if value.key?(key)
        end

      when "array"
        raise Error, "#{path} must be an array" unless value.is_a?(Array)

        if schema["items"]
          value.each_with_index do |item, i|
            validate_node!(item, schema["items"], "#{path}[#{i}]")
          end
        end

      when "string"
        raise Error, "#{path} must be a string" unless value.is_a?(String)

      when "number", "integer"
        raise Error, "#{path} must be a number" unless value.is_a?(Numeric)

      when "boolean"
        raise Error, "#{path} must be a boolean" unless value == true || value == false
      end
    end
  end
end
