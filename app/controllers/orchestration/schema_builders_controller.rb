# frozen_string_literal: true

module Orchestration
  class SchemaBuildersController < ApplicationController
    def build
      root = SchemaBuilder.from_schema(parse_json)
      if params[:builder].present?
        root = apply_inline_params(root, parse_path, params[:builder])
      end
      @builder = root
      @json = @builder.to_schema.to_json
      render :build
    end

    def add_property
      name = params[:property_name].to_s.strip
      root = SchemaBuilder.from_schema(parse_json)
      @builder = root.with_mutation(parse_path) { |b| b.add_property(name) }
      @json = @builder.to_schema.to_json
      render :build
    end

    def remove_property
      name = params[:property_name].to_s.strip
      root = SchemaBuilder.from_schema(parse_json)
      @builder = root.with_mutation(parse_path) { |b| b.remove_property(name) }
      @json = @builder.to_schema.to_json
      render :build
    end

    def change_type
      new_type = params[:new_type].to_s
      root = SchemaBuilder.from_schema(parse_json)
      @builder =
        if SchemaBuilder::TYPES.include?(new_type)
          root.with_mutation(parse_path) { |b| b.with_type(new_type) }
        else
          root
        end
      @json = @builder.to_schema.to_json
      render :build
    end

    def parse
      parsed = JSON.parse(params[:json].to_s)
      unless parsed.is_a?(Hash)
        @error = "Invalid JSON: expected an object, got #{parsed.class.name.downcase}"
        return render :parse_error, status: :unprocessable_entity
      end
      @builder = SchemaBuilder.from_schema(parsed)
      @json = @builder.to_schema.to_json
      render :build
    rescue JSON::ParserError
      @error = "Invalid JSON: #{$!.message}"
      render :parse_error, status: :unprocessable_entity
    end

    private

    def parse_json
      parsed = JSON.parse(params[:json].to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def parse_path
      JSON.parse(params[:path].to_s)
    rescue JSON::ParserError
      []
    end

    def apply_inline_params(root, path, builder_params)
      root.with_mutation(path) do |node|
        schema = node.to_schema

        apply_description(schema, builder_params)
        apply_enum(schema, node, builder_params)
        apply_minimum(schema, node, builder_params)
        apply_maximum(schema, node, builder_params)
        apply_required_toggle(schema, builder_params)
        apply_additional_properties(schema, builder_params)

        SchemaBuilder.from_schema(schema)
      end
    end

    def apply_description(schema, builder_params)
      return unless builder_params.key?(:description)

      desc = builder_params[:description].to_s.strip
      desc.present? ? schema["description"] = desc : schema.delete("description")
    end

    def apply_enum(schema, node, builder_params)
      return unless builder_params.key?(:enum_text)

      values = builder_params[:enum_text].to_s.split("\n").map(&:strip).reject(&:blank?)
      return schema.delete("enum") if values.empty?

      schema["enum"] =
        case node.type
        when "integer" then values.map(&:to_i)
        when "number"  then values.map(&:to_f)
        else values
        end
    end

    def apply_minimum(schema, node, builder_params)
      return unless builder_params.key?(:minimum)

      val = builder_params[:minimum].to_s.strip
      if val.present?
        schema["minimum"] = node.type == "integer" ? val.to_i : val.to_f
      else
        schema.delete("minimum")
      end
    end

    def apply_maximum(schema, node, builder_params)
      return unless builder_params.key?(:maximum)

      val = builder_params[:maximum].to_s.strip
      if val.present?
        schema["maximum"] = node.type == "integer" ? val.to_i : val.to_f
      else
        schema.delete("maximum")
      end
    end

    def apply_required_toggle(schema, builder_params)
      return unless builder_params[:required_toggle].present?

      prop = builder_params[:required_toggle]
      req = Array(schema["required"])
      req = builder_params[:required_checked] == "true" ? (req + [ prop ]).uniq : req - [ prop ]
      req.any? ? schema["required"] = req : schema.delete("required")
    end

    def apply_additional_properties(schema, builder_params)
      return unless builder_params[:additional_properties_toggle] == "true"

      schema["additionalProperties"] = builder_params[:additional_properties] == "true"
    end
  end
end
