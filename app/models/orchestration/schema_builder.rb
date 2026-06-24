# frozen_string_literal: true

module Orchestration
  # rubocop:disable Metrics/ClassLength
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

    def self.from_schema(schema)
      return new if schema.blank?

      schema = schema.deep_stringify_keys
      new(**build_from_schema(schema))
    end

    def self.from_params(params)
      return new if params.blank?

      params = params.to_h.deep_stringify_keys
      new(**build_from_params(params))
    end

    def self.build_from_schema(schema)
      children = parse_schema_children(schema)
      { **parse_schema_scalars(schema), **children }
    end
    private_class_method :build_from_schema

    def self.parse_schema_children(schema)
      properties = (schema["properties"] || empty_object).transform_values { |v| from_schema(v) }
      items = schema["items"].present? ? from_schema(schema["items"]) : nil
      { properties: properties, items: items }
    end
    private_class_method :parse_schema_children

    def self.parse_schema_scalars(schema)
      {
        type: schema["type"],
        description: schema["description"],
        format: schema["format"],
        required: Array(schema["required"]),
        additional_properties: schema.key?("additionalProperties") ? schema["additionalProperties"] : nil,
        enum: Array(schema["enum"]),
        minimum: schema["minimum"],
        maximum: schema["maximum"]
      }
    end
    private_class_method :parse_schema_scalars

    def self.build_from_params(params)
      children = parse_params_children(params)
      { **parse_params_scalars(params), **children }
    end
    private_class_method :build_from_params

    def self.parse_params_children(params)
      properties = (params["properties"] || empty_object).transform_values { |v| from_params(v) }
      items = params["items"].present? ? from_params(params["items"]) : nil
      { properties: properties, items: items }
    end
    private_class_method :parse_params_children

    def self.parse_params_scalars(params)
      {
        **parse_params_text_fields(params),
        required: Array(params["required"]).compact_blank,
        additional_properties: parse_additional_properties(params),
        enum: Array(params["enum"]).compact_blank,
        **parse_params_numeric_bounds(params)
      }
    end
    private_class_method :parse_params_scalars

    def self.parse_params_text_fields(params)
      {
        type: params["type"].presence,
        description: params["description"].presence,
        format: params["format"].presence
      }
    end
    private_class_method :parse_params_text_fields

    def self.parse_params_numeric_bounds(params)
      {
        minimum: coerce_number(params["minimum"], params["type"]),
        maximum: coerce_number(params["maximum"], params["type"])
      }
    end
    private_class_method :parse_params_numeric_bounds

    def self.parse_additional_properties(params)
      case params["additionalProperties"]
      when "true"  then true
      when "false" then false
      else params.key?("additionalProperties") ? params["additionalProperties"] : nil
      end
    end
    private_class_method :parse_additional_properties

    def to_schema
      schema = empty_object
      apply_basic_fields!(schema)
      apply_format_field!(schema)
      apply_type_specific_fields!(schema)
      apply_numeric_bounds!(schema)
      schema
    end

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

    def apply_basic_fields!(schema)
      schema["type"] = type if type.present?
      schema["description"] = description if description.present?
      schema["enum"] = enum if ENUM_TYPES.include?(type) && enum.present?
    end

    def apply_format_field!(schema)
      schema["format"] = format if format.present? && (type == "string" || format == "hardcoded")
    end

    def apply_type_specific_fields!(schema)
      if type == "object"
        apply_object_fields!(schema)
      elsif type == "array"
        schema["items"] = items.to_schema if items.present?
      end
    end

    def apply_object_fields!(schema)
      schema["required"] = required if required.present?
      schema["additionalProperties"] = additional_properties unless additional_properties.nil?
      schema["properties"] = properties.transform_values(&:to_schema) if properties.present?
    end

    def apply_numeric_bounds!(schema)
      return unless NUMERIC_TYPES.include?(type)

      schema["minimum"] = minimum unless minimum.nil?
      schema["maximum"] = maximum unless maximum.nil?
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

    def self.coerce_number(value, type)
      return nil if value.blank?

      type == "integer" ? value.to_i : value.to_f
    end
    private_class_method :coerce_number
  end
  # rubocop:enable Metrics/ClassLength
end
