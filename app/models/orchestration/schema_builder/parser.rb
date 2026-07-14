# frozen_string_literal: true

module Orchestration
  class SchemaBuilder
    # Builds a SchemaBuilder tree from a JSON-schema hash or from form params.
    # Recurses through children via self.from_schema/self.from_params so nested
    # parsing stays inside the Parser rather than bouncing through the model.
    class Parser
      class << self
        include SteepHacks

        def from_schema(schema)
          return SchemaBuilder.new if schema.blank?

          schema = schema.deep_stringify_keys
          SchemaBuilder.new(**build_from_schema(schema))
        end

        def from_params(params)
          return SchemaBuilder.new if params.blank?

          params = params.to_h.deep_stringify_keys
          SchemaBuilder.new(**build_from_params(params))
        end

        private

        def build_from_schema(schema)
          children = parse_schema_children(schema)
          { **parse_schema_scalars(schema), **children }
        end

        def parse_schema_children(schema)
          properties = (schema["properties"] || empty_object).transform_values { |v| from_schema(v) }
          items = schema["items"].present? ? from_schema(schema["items"]) : nil
          { properties: properties, items: items }
        end

        def parse_schema_scalars(schema)
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

        def build_from_params(params)
          children = parse_params_children(params)
          { **parse_params_scalars(params), **children }
        end

        def parse_params_children(params)
          properties = (params["properties"] || empty_object).transform_values { |v| from_params(v) }
          items = params["items"].present? ? from_params(params["items"]) : nil
          { properties: properties, items: items }
        end

        def parse_params_scalars(params)
          {
            **parse_params_text_fields(params),
            required: Array(params["required"]).compact_blank,
            additional_properties: parse_additional_properties(params),
            enum: Array(params["enum"]).compact_blank,
            **parse_params_numeric_bounds(params)
          }
        end

        def parse_params_text_fields(params)
          {
            type: params["type"].presence,
            description: params["description"].presence,
            format: params["format"].presence
          }
        end

        def parse_params_numeric_bounds(params)
          {
            minimum: coerce_number(params["minimum"], params["type"]),
            maximum: coerce_number(params["maximum"], params["type"])
          }
        end

        def parse_additional_properties(params)
          case params["additionalProperties"]
          when "true"  then true
          when "false" then false
          else params.key?("additionalProperties") ? params["additionalProperties"] : nil
          end
        end

        def coerce_number(value, type)
          return nil if value.blank?

          type == "integer" ? value.to_i : value.to_f
        end
      end
    end
  end
end
