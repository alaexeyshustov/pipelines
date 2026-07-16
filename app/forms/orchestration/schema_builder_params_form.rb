
module Orchestration
  class SchemaBuilderParamsForm < ::BaseForm
    def initialize(params = {})
      @params = params || {}
    end

    def apply(node)
      schema = node.to_schema
      apply_string_field(schema, :description)
      apply_string_field(schema, :format)
      apply_enum(schema, node)
      apply_numeric_bound(schema, node, :minimum)
      apply_numeric_bound(schema, node, :maximum)
      apply_required_toggle(schema)
      apply_additional_properties(schema)
      SchemaBuilder.from_schema(schema)
    end

    private

    def provided?(key) = @params.key?(key)

    def apply_string_field(schema, key)
      return unless provided?(key)

      value = @params[key].to_s.strip
      value.present? ? schema[key.to_s] = value : schema.delete(key.to_s)
    end

    def apply_enum(schema, node)
      return unless provided?(:enum_text)

      values = @params[:enum_text].to_s.split("\n").map(&:strip).compact_blank
      return schema.delete("enum") if values.empty?

      schema["enum"] = coerce_enum_values(values, node.type)
    end

    def coerce_enum_values(values, type)
      case type
      when "integer" then values.map(&:to_i)
      when "number"  then values.map(&:to_f)
      else values
      end
    end

    def apply_numeric_bound(schema, node, key)
      return unless provided?(key)

      val = @params[key].to_s.strip
      if val.present?
        schema[key.to_s] = node.type == "integer" ? val.to_i : val.to_f
      else
        schema.delete(key.to_s)
      end
    end

    def apply_required_toggle(schema)
      return if @params[:required_toggle].blank?

      prop = @params[:required_toggle]
      req = Array(schema["required"])
      req = @params[:required_checked] == "true" ? (req + [ prop ]).uniq : req - [ prop ]
      req.any? ? schema["required"] = req : schema.delete("required")
    end

    def apply_additional_properties(schema)
      return unless @params[:additional_properties_toggle] == "true"

      schema["additionalProperties"] = @params[:additional_properties] == "true"
    end
  end
end
