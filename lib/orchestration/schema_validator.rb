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

    SCALAR_TYPES = {
      "string"  => [ String ],
      "integer" => [ Integer ],
      "number"  => [ Numeric ],
      "boolean" => [ TrueClass, FalseClass ]
    }.freeze

    private

    def validate_node!(value, schema, path)
      return if schema.nil?

      case schema["type"]
      when "object" then validate_object!(value, schema, path)
      when "array"  then validate_array!(value, schema, path)
      else               validate_scalar_type!(value, schema, path)
      end
    end

    def validate_object!(value, schema, path)
      raise Error, "#{path} must be an object" unless value.is_a?(Hash)

      validate_required_keys!(value, schema["required"], path)
      validate_object_properties!(value, schema["properties"], path)
    end

    def validate_required_keys!(value, required, path)
      return unless required.is_a?(Array)

      required.each do |key| # steep:ignore
        next unless key.is_a?(String)

        raise Error, "#{path} missing required key: #{key}" unless value.key?(key)
      end
    end

    def validate_object_properties!(value, properties, path)
      return unless properties.is_a?(Hash)

      properties.each do |key, sub_schema|
        next unless key.is_a?(String)
        next unless sub_schema.is_a?(Hash)

        validate_node!(value[key], sub_schema, "#{path}.#{key}") if value.key?(key)
      end
    end

    def validate_array!(value, schema, path)
      raise Error, "#{path} must be an array" unless value.is_a?(Array)

      items = schema["items"]
      if items.is_a?(Hash)
        value.each_with_index { |item, i| validate_node!(item, items, "#{path}[#{i}]") }
      end
    end

    def validate_scalar_type!(value, schema, path)
      raw_type = schema["type"]
      return unless raw_type.is_a?(String)

      type = raw_type # : String
      expected = SCALAR_TYPES[type]
      return unless expected

      return if expected.any? { |klass| value.is_a?(klass) }

      article = %w[integer].include?(type) ? "an" : "a"
      raise Error, "#{path} must be #{article} #{type}"
    end
  end
end
