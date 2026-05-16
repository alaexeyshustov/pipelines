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
      @builder = root.with_mutation(parse_path) { |b| b.with_type(new_type) }
      @json = @builder.to_schema.to_json
      render :build
    end

    def parse
      @builder = SchemaBuilder.from_schema(JSON.parse(params[:json].to_s))
      @json = @builder.to_schema.to_json
      render :build
    rescue JSON::ParserError
      @error = "Invalid JSON: #{$!.message}"
      render :parse_error, status: :unprocessable_entity
    end

    private

    def parse_json
      JSON.parse(params[:json].to_s)
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

        if builder_params.key?(:description)
          desc = builder_params[:description].to_s.strip
          desc.present? ? schema["description"] = desc : schema.delete("description")
        end

        if builder_params.key?(:enum_text)
          values = builder_params[:enum_text].to_s.split("\n").map(&:strip).reject(&:blank?)
          values.any? ? schema["enum"] = values : schema.delete("enum")
        end

        if builder_params[:minimum].present?
          schema["minimum"] = node.type == "integer" ? builder_params[:minimum].to_i : builder_params[:minimum].to_f
        end

        if builder_params[:maximum].present?
          schema["maximum"] = node.type == "integer" ? builder_params[:maximum].to_i : builder_params[:maximum].to_f
        end

        if builder_params[:required_toggle].present?
          prop = builder_params[:required_toggle]
          req = Array(schema["required"])
          req = builder_params[:required_checked] == "true" ? (req + [ prop ]).uniq : req - [ prop ]
          req.any? ? schema["required"] = req : schema.delete("required")
        end

        if builder_params[:additional_properties_toggle] == "true"
          schema["additionalProperties"] = builder_params[:additional_properties] == "true"
        end

        SchemaBuilder.from_schema(schema)
      end
    end
  end
end
