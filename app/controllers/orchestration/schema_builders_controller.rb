
module Orchestration
  class SchemaBuildersController < ApplicationController
    def build
      root = SchemaBuilder.from_schema(parse_json)
      if params[:builder].present?
        root = root.with_mutation(parse_path) { |node| SchemaBuilderParamsForm.new(builder_params).apply(node) }
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
      return render_parse_error("Invalid JSON: expected an object, got #{parsed.class.name.downcase}") unless parsed.is_a?(Hash)

      @builder = SchemaBuilder.from_schema(parsed)
      @json = @builder.to_schema.to_json
      render :build
    rescue JSON::ParserError
      render_parse_error("Invalid JSON: #{$!.message}")
    end

    private

    def render_parse_error(message)
      @error = message
      render :parse_error, status: :unprocessable_content
    end

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

    def builder_params
      params.fetch(:builder, {}).permit(
        :description, :format, :enum_text, :minimum, :maximum,
        :required_toggle, :required_checked,
        :additional_properties_toggle, :additional_properties
      )
    end
  end
end
