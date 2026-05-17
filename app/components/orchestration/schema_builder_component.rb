# frozen_string_literal: true

module Orchestration
  class SchemaBuilderComponent < ViewComponent::Base
    attr_reader :builder, :path, :json

    def initialize(builder:, path: [], json: nil)
      @builder = builder
      @path = path
      @json = json || builder.to_schema.to_json
    end

    def root?
      path.empty?
    end

    def type_options
      SchemaBuilder::TYPES.map { |t| [ t, t ] }
    end

    def path_json
      path.to_json
    end

    def required?(prop_name)
      builder.required.include?(prop_name)
    end

    def add_property_url
      helpers.add_property_orchestration_schema_builders_path
    end

    def remove_property_url
      helpers.remove_property_orchestration_schema_builders_path
    end

    def change_type_url
      helpers.change_type_orchestration_schema_builders_path
    end

    def parse_url
      helpers.parse_orchestration_schema_builders_path
    end
  end
end
