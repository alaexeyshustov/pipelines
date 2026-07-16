
module Orchestration
  class SchemaBuilder
    class Serializer
      include SteepHacks

      def initialize(builder)
        @builder = builder
      end

      def call
        serialize(@builder)
      end

      private

      def serialize(builder)
        schema = empty_object
        apply_basic_fields!(schema, builder)
        apply_format_field!(schema, builder)
        apply_type_specific_fields!(schema, builder)
        apply_numeric_bounds!(schema, builder)
        schema
      end

      def apply_basic_fields!(schema, builder)
        schema["type"] = builder.type if builder.type.present?
        schema["description"] = builder.description if builder.description.present?
        schema["enum"] = builder.enum if ENUM_TYPES.include?(builder.type) && builder.enum.present?
      end

      def apply_format_field!(schema, builder)
        return if builder.format.blank?

        schema["format"] = builder.format if builder.type == "string" || builder.format == "hardcoded"
      end

      def apply_type_specific_fields!(schema, builder)
        if builder.type == "object"
          apply_object_fields!(schema, builder)
        elsif builder.type == "array"
          schema["items"] = serialize(builder.items) if builder.items.present?
        end
      end

      def apply_object_fields!(schema, builder)
        schema["required"] = builder.required if builder.required.present?
        schema["additionalProperties"] = builder.additional_properties unless builder.additional_properties.nil?
        schema["properties"] = builder.properties.transform_values { |child| serialize(child) } if builder.properties.present?
      end

      def apply_numeric_bounds!(schema, builder)
        return unless NUMERIC_TYPES.include?(builder.type)

        schema["minimum"] = builder.minimum unless builder.minimum.nil?
        schema["maximum"] = builder.maximum unless builder.maximum.nil?
      end
    end
  end
end
