module Orchestration
  class SchemaValidator
    Error = Class.new(StandardError)

    def initialize(schema)
      @schema = schema
    end

    def validate!(data)
      return if @schema.nil?

      validate_node!(data, @schema, "data")
    end

    private

    def validate_node!(value, schema, path)
      return if schema.nil?

      case schema["type"]
      when "object"
        raise Error, "#{path} must be an object" unless value.is_a?(Hash)

        required = schema["required"]
        Array(required).each do |key|
          next unless key.is_a?(String)

          raise Error, "#{path} missing required key: #{key}" unless value.key?(key)
        end

        # JSON Schema: properties not present in data are valid (only required enforces presence)
        properties = schema["properties"]
        if properties.is_a?(Hash)
          properties.each do |key, sub_schema|
            next unless key.is_a?(String)
            next unless sub_schema.is_a?(Hash)

            validate_node!(value[key], sub_schema, "#{path}.#{key}") if value.key?(key)
          end
        end

      when "array"
        raise Error, "#{path} must be an array" unless value.is_a?(Array)

        items = schema["items"]
        if items.is_a?(Hash)
          value.each_with_index do |item, i|
            validate_node!(item, items, "#{path}[#{i}]")
          end
        end

      when "string"
        raise Error, "#{path} must be a string" unless value.is_a?(String)

      when "integer"
        raise Error, "#{path} must be an integer" unless value.is_a?(Integer)

      when "number"
        raise Error, "#{path} must be a number" unless value.is_a?(Numeric)

      when "boolean"
        raise Error, "#{path} must be a boolean" unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
      end
    end
  end
end
