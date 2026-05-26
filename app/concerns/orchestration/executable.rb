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

      private

      def build_input_schema!
        declared = @_input_schema_types
        params   = method(:call).parameters
        keywords = params.select { |type, _| type == :keyreq || type == :key }
                         .map { |_, name| name.to_s }

        extra_declared = declared.keys - keywords
        missing_types  = keywords - declared.keys

        if extra_declared.any?
          raise ArgumentError,
            "#{name}: input_schema declares types for undeclared keyword args: #{extra_declared.join(', ')}"
        end

        if missing_types.any?
          raise ArgumentError,
            "#{name}: keyword args missing from input_schema declaration: #{missing_types.join(', ')}"
        end

        required = params.select { |type, _| type == :keyreq }.map { |_, name| name.to_s }

        schema = {
          "type"       => "object",
          "properties" => declared.transform_values { |v| v.transform_keys(&:to_s) }
        }
        schema["required"] = required if required.any?
        schema
      end
    end
  end
end
