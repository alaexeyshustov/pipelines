module Orchestration
  class PipelineImporter
    # Shape checks for untrusted parsed JSON; each raises ImportError on mismatch.
    module Shape
      private

      def slice(data, keys)
        data.slice(*keys)
      end

      def hash!(value, label)
        return value if value.is_a?(Hash)

        raise ImportError, "#{label} must be an object"
      end

      def required_array!(value, label)
        raise ImportError, "#{label} is required" if value.nil?

        array!(value, label)
      end

      def array!(value, label)
        return [] if value.nil?
        return value if value.is_a?(Array)

        raise ImportError, "#{label} must be an array"
      end
    end
  end
end
