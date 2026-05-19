module Orchestration
  class Pipeline
    class Validator
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
        @pipeline.steps.includes(step_actions: :action).flat_map do |step|
          step.step_actions.sort_by(&:position)
        end
      end

      def validate_input_mapping(step_action, known_schemas, errors, warnings)
        mapping = step_action.input_mapping || {}

        mapping.each do |mapping_key, spec|
          next unless spec.is_a?(Hash)

          from = spec["from"]
          path = spec["path"]

          if known_schemas.key?(from)
            validate_path_vs_schema(from, path, mapping_key, known_schemas[from], errors)
          else
            errors << Issue.new(
              code: :unknown_from,
              message: "input_mapping key #{mapping_key.inspect} references unknown output key #{from.inspect}",
              mapping_key: mapping_key,
              from: from,
              path: nil
            )
          end

          if merge_params(step_action).key?(mapping_key)
            warnings << Issue.new(
              code: :param_collision,
              message: "key #{mapping_key.inspect} appears in both input_mapping and params; input_mapping wins at runtime",
              mapping_key: mapping_key,
              from: from,
              path: nil
            )
          end
        end
      end

      def validate_path_vs_schema(from, path, mapping_key, upstream_schema, errors)
        return if path.nil? || upstream_schema.nil?

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
            properties = current["properties"] || {}
            return false unless properties.key?(seg)

            current = properties[seg]
          when "array"
            return false unless seg.match?(/\A\d+\z/)

            current = current["items"]
          else
            return false
          end
        end

        true
      end

      def merge_params(step_action)
        (step_action.action.params || {}).merge(step_action.params || {})
      end
    end
  end
end
