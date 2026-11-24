module Orchestration
  module Executable
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def input_schema(declared_types = nil)
        if declared_types
          @_input_schema_types = declared_types.transform_keys(&:to_s)
        else
          return nil unless @_input_schema_types

          @_input_schema ||= build_input_schema!
        end
      end

      # Declares the shape of the hash +call+ returns, so the validator and the steps list can check the paths a later
      # step maps from this one. Every declared key is required; unlike input_schema it is not checked against
      # +initialize+.
      def output_schema(**properties)
        if properties.any?
          @_output_schema_properties = properties.deep_stringify_keys
          @_output_schema = nil
        else
          declared = @_output_schema_properties
          return nil unless declared

          @_output_schema ||= { "type" => "object", "properties" => declared, "required" => declared.keys }
        end
      end

      private

      def build_input_schema!
        declared = @_input_schema_types
        params   = instance_method(:initialize).parameters
        keywords = extract_keyword_names(params)

        validate_schema_consistency!(declared, keywords)

        required = params.select { |type, _| type == :keyreq }.map { |_, name| name.to_s }

        schema = {
          "type"       => "object",
          "properties" => declared.transform_values { |v| v.transform_keys(&:to_s) }
        }
        schema["required"] = required if required.any?
        schema
      end

      def extract_keyword_names(params)
        params.select { |type, _| type == :keyreq || type == :key }
              .map { |_, name| name.to_s }
      end

      def validate_schema_consistency!(declared, keywords)
        extra_declared = declared.keys - keywords
        missing_types  = keywords - declared.keys

        if extra_declared.any?
          raise ArgumentError,
            "#{name}: input_schema declares types for undeclared keyword args: #{extra_declared.join(', ')}"
        end

        return unless missing_types.any?

        raise ArgumentError,
          "#{name}: keyword args missing from input_schema declaration: #{missing_types.join(', ')}"
      end
    end
  end
end
