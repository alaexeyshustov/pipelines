
module Orchestration
  class SchemaBuilder
    include SteepHacks
    extend SteepHacks

    TYPES = %w[string integer number boolean object array].freeze
    ENUM_TYPES = %w[string integer number].freeze
    NUMERIC_TYPES = %w[integer number].freeze

    attr_reader :type, :description, :format, :required, :additional_properties,
                :properties, :items, :enum, :minimum, :maximum

    def initialize(
      type: nil,
      description: nil,
      format: nil,
      required: [],
      additional_properties: nil,
      properties: {},
      items: nil,
      enum: [],
      minimum: nil,
      maximum: nil
    )
      @type = type
      @description = description
      @format = format
      @required = Array(required).compact
      @additional_properties = additional_properties
      @properties = properties
      @items = items
      @enum = Array(enum).compact
      @minimum = minimum
      @maximum = maximum
    end

    def self.from_schema(schema) = Parser.from_schema(schema)
    def self.from_params(params) = Parser.from_params(params)

    def to_schema = Serializer.new(self).call

    def add_property(name)
      return self if name.blank? || properties.key?(name)

      new_properties = properties.merge(name => SchemaBuilder.new(type: "string"))
      dup_with(properties: new_properties)
    end

    def remove_property(name)
      dup_with(
        properties: properties.except(name),
        required: required - [ name ]
      )
    end

    def with_type(new_type)
      SchemaBuilder.new(type: new_type, description: description)
    end

    def with_mutation(path, &block)
      return yield(self) if path.empty?

      key, *rest = path
      case key
      when "properties" then with_property_mutation(rest, &block)
      when "items"      then with_items_mutation(rest, &block)
      else self
      end
    end

    private

    def with_property_mutation(rest, &block)
      prop_name = rest.first
      rest_path = rest.drop(1)
      current_prop = properties.fetch(prop_name, SchemaBuilder.new)
      new_prop = current_prop.with_mutation(rest_path, &block)
      dup_with(properties: properties.merge(prop_name => new_prop))
    end

    def with_items_mutation(rest, &block)
      new_items = (items || SchemaBuilder.new(type: "string")).with_mutation(rest, &block)
      dup_with(items: new_items)
    end

    def dup_with(**overrides)
      SchemaBuilder.new(
        type: type,
        description: description,
        format: format,
        required: required.dup,
        additional_properties: additional_properties,
        properties: properties.dup,
        items: items,
        enum: enum.dup,
        minimum: minimum,
        maximum: maximum,
        **overrides
      )
    end
  end
end
