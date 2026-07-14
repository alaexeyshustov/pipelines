module Orchestration
  class PipelineValidator
    include SteepHacks

    Issue = Data.define(:code, :message, :mapping_key, :from, :path)
    StepResult = Data.define(:step_action_id, :output_key, :errors, :warnings)

    def initialize(pipeline)
      @pipeline = pipeline
    end

    def validate
      known_schemas = { "_initial" => @pipeline.initial_input_schema }
      ordered_step_actions.map do |sa|
        result = validate_step_action(sa, known_schemas)
        known_schemas[sa.output_key] = sa.action.agent&.output_schema
        result
      end
    end

    private

    def validate_step_action(sa, known_schemas)
      errors   = [] # : Array[Issue]
      warnings = [] # : Array[Issue]
      validate_input_mapping(sa, known_schemas, errors, warnings)
      validate_input_schema_coverage(sa, warnings)
      StepResult.new(step_action_id: sa.id, output_key: sa.output_key, errors: errors, warnings: warnings)
    end

    def ordered_step_actions
      steps = @pipeline.steps_with_actions.to_a # : Array[Orchestration::Step]
      steps.flat_map do |step|
        step_actions = step.step_actions.to_a # : Array[Orchestration::StepAction]
        step_actions.sort_by { |sa| sa.position.to_i }
      end
    end

    def validate_input_mapping(step_action, known_schemas, errors, _warnings)
      mapping = step_action.input_mapping || empty_object

      mapping.each do |mapping_key, spec|
        next unless mapping_key.is_a?(String)
        next unless spec.is_a?(Hash)

        process_mapping_spec(mapping_key, spec, known_schemas, errors)
      end
    end

    def process_mapping_spec(mapping_key, spec, known_schemas, errors)
      return if spec.key?("value")

      from = spec["from"]
      return unless from.is_a?(String)

      resolved_path = spec["path"].is_a?(String) ? spec["path"] : nil
      return if add_unknown_from_error(mapping_key, from, known_schemas, errors)

      schema = known_schemas[from]
      return unless schema.is_a?(Hash)

      validate_path_vs_schema(from, resolved_path, mapping_key, schema.transform_keys(&:to_s), errors)
    end

    def add_unknown_from_error(mapping_key, from, known_schemas, errors)
      return false if known_schemas.key?(from)

      errors << Issue.new(
        code: :unknown_from,
        message: "input_mapping key #{mapping_key.inspect} references unknown output key #{from.inspect}",
        mapping_key: mapping_key,
        from: from,
        path: nil
      )
      true
    end

    def validate_input_schema_coverage(step_action, warnings)
      schema = step_action.action.input_schema
      return unless schema

      required_keys = Array(schema["required"]).filter_map { |key| key if key.is_a?(String) }
      covered_keys  = (step_action.input_mapping || empty_object).keys

      required_keys.each do |key|
        next if covered_keys.include?(key)

        warnings << Issue.new(
          code: :missing_required_input,
          message: "input_schema requires #{key.inspect} but input_mapping has no entry for it",
          mapping_key: key,
          from: nil,
          path: nil
        )
      end
    end

    def validate_path_vs_schema(from, path, mapping_key, upstream_schema, errors)
      return if path.blank? || upstream_schema.nil?

      return if SchemaPathValidator.valid?(path, upstream_schema)

      errors << Issue.new(
        code: :invalid_path,
        message: "path #{path.inspect} does not resolve in output_schema of #{from.inspect}",
        mapping_key: mapping_key,
        from: from,
        path: path
      )
    end
  end
end
