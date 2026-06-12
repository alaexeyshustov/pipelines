# frozen_string_literal: true

module Orchestration
  class PipelineRunForm < ::BaseForm
    include SteepHacks

    attr_reader :pipeline_run

    validate :no_active_run
    validate :initial_input_valid

    def initialize(pipeline:, initial_input_params: nil)
      @pipeline = pipeline
      @initial_input_params = initial_input_params
    end

    def save
      return false unless valid?

      @pipeline_run = @pipeline.pipeline_runs.create(
        status: "pending",
        triggered_by: "manual",
        initial_input: extract_initial_input
      )
      @pipeline_run.persisted?
    end

    private

    def no_active_run
      return unless @pipeline.pipeline_runs.exists?(status: %w[pending running])

      errors.add(:base, "A run is already pending.")
    end

    def initial_input_valid
      return unless @pipeline.initial_input_schema.present?

      Orchestration::SchemaValidator.new(@pipeline.initial_input_schema).validate!(extract_initial_input)
    rescue Orchestration::SchemaValidator::Error => e
      errors.add(:base, e.message)
    end

    def extract_initial_input
      return @extracted_input if defined?(@extracted_input)

      @extracted_input = if @pipeline.initial_input_schema.blank?
        nil
      else
        user_input = @initial_input_params&.to_unsafe_h&.deep_stringify_keys || empty_object
        user_input.merge(hardcoded_values(@pipeline.initial_input_schema))
      end
    end

    def hardcoded_values(schema)
      collector = {} # : Hash[String, json_object_value]
      (schema["properties"] || empty_object).each_with_object(collector) do |(key, prop), memo|
        next unless prop["format"] == "hardcoded"

        memo[key] = hardcoded_value_for(prop)
      end
    end

    def hardcoded_value_for(prop)
      if prop["type"] == "array"
        prop["const"] || prop.dig("items", "enum") || []
      else
        prop["const"] || prop["enum"]&.first
      end
    end
  end
end
