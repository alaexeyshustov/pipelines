module Orchestration
  class Pipeline
    class Validator
      include SteepHacks

      Issue = Data.define(:code, :message, :mapping_key, :from, :path)
      StepResult = Data.define(:step_action_id, :output_key, :errors, :warnings)

      def self.call(pipeline) = new(pipeline).call

      def initialize(pipeline)
        @pipeline = pipeline
      end

      def call
        known_schemas = { "_initial" => @pipeline.initial_input_schema }
        results = [] # : Array[StepResult]

        ordered_step_actions.each do |sa|
          errors   = [] # : Array[Issue]
          warnings = [] # : Array[Issue]

          validate_input_mapping(sa, known_schemas, errors, warnings)
          validate_input_schema_coverage(sa, warnings)

          results << StepResult.new(
            step_action_id: sa.id,
            output_key: sa.output_key,
            errors: errors,
            warnings: warnings
          )

          known_schemas[sa.output_key] = sa.action.agent&.output_schema
        end

        results
      end

      private

      def ordered_step_actions
        steps = @pipeline.steps.includes(step_actions: { action: :agent }).to_a # : Array[Orchestration::Step]
        steps.flat_map do |step|
          step_actions = step.step_actions.to_a # : Array[Orchestration::StepAction]
          step_actions.sort_by { |sa| sa.position.to_i }
        end
      end

      def validate_input_mapping(step_action, known_schemas, errors, warnings)
        mapping = step_action.input_mapping || empty_object

        mapping.each do |mapping_key, spec|
          next unless mapping_key.is_a?(String)
          next unless spec.is_a?(Hash)
          next if spec.key?("value")

          from = spec["from"]
          next unless from.is_a?(String)
          path = spec["path"]
          resolved_path = path.is_a?(String) ? path : nil
          unless known_schemas.key?(from)
            errors << Issue.new(
              code: :unknown_from,
              message: "input_mapping key #{mapping_key.inspect} references unknown output key #{from.inspect}",
              mapping_key: mapping_key,
              from: from,
              path: nil
            )
            next
          end

          schema = known_schemas[from]
          next unless schema.is_a?(Hash)

          validate_path_vs_schema(from, resolved_path, mapping_key, schema.transform_keys(&:to_s), errors)
        end
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
        return if path.nil? || path.empty? || upstream_schema.nil?

        return if path_valid_in_schema?(path, upstream_schema)

        errors << Issue.new(
          code: :invalid_path,
          message: "path #{path.inspect} does not resolve in output_schema of #{from.inspect}",
          mapping_key: mapping_key,
          from: from,
          path: path
        )
      end

      def path_valid_in_schema?(path, schema)
        current = schema

        path.split(".").each do |seg|
          return false if current.nil?

          case current["type"]
          when "object"
            properties = current["properties"]
            return false unless properties.is_a?(Hash)
            return false unless properties.key?(seg)

            current = properties[seg]
          when "array"
            return false unless seg.match?(/\A\d+\z/)

            current = current["items"].is_a?(Hash) ? current["items"] : nil
          else
            return false
          end
        end

        true
      end
    end
  end
end
