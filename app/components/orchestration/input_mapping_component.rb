# frozen_string_literal: true

module Orchestration
  class InputMappingComponent < ViewComponent::Base
    MappingRow = Data.define(:mapping_key, :current_from, :current_path, :path_opts)

    def initialize(step_action:, pipeline:, step:, upstream_schemas:)
      @step_action      = step_action
      @pipeline         = pipeline
      @step             = step
      @upstream_schemas = upstream_schemas
    end

    def form_url
      helpers.orchestration_pipeline_step_step_action_path(@pipeline, @step, @step_action)
    end

    def from_options
      @upstream_schemas.keys.map { |k| [ k, k ] }
    end

    def path_options_for(from_key)
      schema = @upstream_schemas[from_key]
      return nil if schema.nil?

      paths = schema_paths(schema)
      return nil if paths.empty?

      paths.map { |p| [ p, p ] }
    end

    def mapping
      @step_action.input_mapping || {}
    end

    private

    def schema_paths(schema, prefix = "")
      if schema["properties"].present? || schema["type"] == "object"
        (schema["properties"] || {}).flat_map do |key, child|
          full = prefix.empty? ? key : "#{prefix}.#{key}"
          [ full ] + schema_paths(child, full)
        end
      elsif schema["type"] == "array"
        items = schema["items"]
        return [] if items.nil?
        full = prefix.empty? ? "0" : "#{prefix}.0"
        [ full ] + schema_paths(items, full)
      else
        []
      end
    end

    def mapping_rows
      mapping.map do |mapping_key, spec|
        spec         = spec || {}
        current_from = spec["from"]
        current_path = spec["path"]
        MappingRow.new(
          mapping_key:  mapping_key,
          current_from: current_from,
          current_path: current_path,
          path_opts:    path_options_for(current_from)
        )
      end
    end
  end
end
