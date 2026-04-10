# frozen_string_literal: true

module UI
  class JsonFieldsComponent < ViewComponent::Base
    INPUT_CLASSES    = "w-full border border-gray-300 rounded-lg px-3 py-2 text-sm " \
                       "focus:outline-none focus:ring-2 focus:ring-indigo-500"
    CHECKBOX_CLASSES = "rounded border-gray-300 text-indigo-600"
    LABEL_CLASSES    = "block text-sm font-medium text-gray-700 mb-1"

    def initialize(form:, schema:, name_prefix: nil)
      @form        = form
      @schema      = schema
      @name_prefix = name_prefix
    end

    def fields
      properties.map do |field_name, field_schema|
        {
          name:     field_name,
          schema:   field_schema,
          kind:     field_kind(field_schema),
          required: required_fields.include?(field_name)
        }
      end
    end

    def input_name(field_name, array: false)
      base = @name_prefix ? "#{@name_prefix}[#{field_name}]" : field_name
      array ? "#{base}[]" : base
    end

    private

    def properties
      @schema.fetch("properties", {})
    end

    def required_fields
      @schema.fetch("required", [])
    end

    def field_kind(schema)
      if schema["type"] == "array" && schema.dig("items", "enum").present?
        :checkboxes
      elsif schema["format"] == "date"
        :date
      elsif schema["type"] == "string" && schema["enum"].present?
        :select
      elsif schema["type"] == "boolean"
        :boolean
      elsif %w[integer number].include?(schema["type"])
        :number
      else
        :text
      end
    end
  end
end
