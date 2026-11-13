module Orchestration
  class SchemaBuildersController < ApplicationController
    def build
      return render_builder(parsed_root) if params[:builder].blank?

      render_mutation { |node| SchemaBuilderParamsForm.new(builder_params).apply(node) }
    end

    def add_property
      render_mutation { |node| node.add_property(property_name) }
    end

    def remove_property
      render_mutation { |node| node.remove_property(property_name) }
    end

    def change_type
      new_type = params[:new_type].to_s
      return render_builder(parsed_root) unless SchemaBuilder::TYPES.include?(new_type)

      render_mutation { |node| node.with_type(new_type) }
    end

    def parse
      parsed = JSON.parse(params[:json].to_s)
      return render_parse_error("Invalid JSON: expected an object, got #{parsed.class.name.downcase}") unless parsed.is_a?(Hash)

      render_builder(SchemaBuilder.from_schema(parsed))
    rescue JSON::ParserError
      render_parse_error("Invalid JSON: #{$!.message}")
    end

    private

    # Applies +mutation+ to the node at params[:path] of the submitted schema and renders the result.
    def render_mutation(&mutation)
      render_builder(parsed_root.with_mutation(parse_path, &mutation))
    end

    def render_builder(builder)
      @builder = builder
      @json = builder.to_schema.to_json
      render :build
    end

    def render_parse_error(message)
      @error = message
      render :parse_error, status: :unprocessable_content
    end

    def parsed_root
      SchemaBuilder.from_schema(parse_json)
    end

    def property_name
      params[:property_name].to_s.strip
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
