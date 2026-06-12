# frozen_string_literal: true

module Orchestration
  # TODO: this class is too big and complex
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

      properties = (schema["properties"] || empty_object).transform_values { |v| from_schema(v) }
      items = schema["items"].present? ? from_schema(schema["items"]) : nil

      new(
        type: schema["type"],
        description: schema["description"],
        format: schema["format"],
        required: Array(schema["required"]),
        additional_properties: schema.key?("additionalProperties") ? schema["additionalProperties"] : nil,
        properties: properties,
        items: items,
        enum: Array(schema["enum"]),
        minimum: schema["minimum"],
        maximum: schema["maximum"]
      )
    end

    def self.from_params(params)
      return new if params.blank?

      params = params.to_h.deep_stringify_keys

      properties = (params["properties"] || empty_object).transform_values { |v| from_params(v) }
      items = params["items"].present? ? from_params(params["items"]) : nil

      additional_properties =
        case params["additionalProperties"]
        when "true"  then true
        when "false" then false
        else params.key?("additionalProperties") ? params["additionalProperties"] : nil
        end

      new(
        type: params["type"].presence,
        description: params["description"].presence,
        format: params["format"].presence,
        required: Array(params["required"]).reject(&:blank?),
        additional_properties: additional_properties,
        properties: properties,
        items: items,
        enum: Array(params["enum"]).reject(&:blank?),
        minimum: coerce_number(params["minimum"], params["type"]),
        maximum: coerce_number(params["maximum"], params["type"])
      )
    end

    def to_schema
      schema = empty_object
      schema["type"] = type if type.present?
      schema["description"] = description if description.present?
      schema["format"] = format if format.present? && (type == "string" || format == "hardcoded")

      if type == "object"
        schema["required"] = required if required.present?
        schema["additionalProperties"] = additional_properties unless additional_properties.nil?
        schema["properties"] = properties.transform_values(&:to_schema) if properties.present?
      elsif type == "array"
        schema["items"] = items.to_schema if items.present?
      end

      if ENUM_TYPES.include?(type) && enum.present?
        schema["enum"] = enum
      end

      if NUMERIC_TYPES.include?(type)
        schema["minimum"] = minimum unless minimum.nil?
        schema["maximum"] = maximum unless maximum.nil?
      end

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
      if path.empty?
        yield(self)
      else
        key, *rest = path
        case key
        when "properties"
          prop_name = rest.first
          rest_path = rest.drop(1)
          current_prop = properties.fetch(prop_name, SchemaBuilder.new)
          new_prop = current_prop.with_mutation(rest_path, &block)
          dup_with(properties: properties.merge(prop_name => new_prop))
        when "items"
          new_items = (items || SchemaBuilder.new(type: "string")).with_mutation(rest, &block)
          dup_with(items: new_items)
        else
          self
        end
      end
    end

    private

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
end
