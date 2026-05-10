module Orchestration
  class InputMappingResolver
    class UnknownOutputKey < StandardError; end
    class MissingPath < StandardError; end

    def initialize(input_mapping:, previous_outputs:)
      @input_mapping    = input_mapping
      @previous_outputs = previous_outputs
    end

    def resolve
      @input_mapping.transform_values do |spec|
        from     = spec["from"]
        path     = spec["path"]
        optional = spec["optional"]

        upstream = fetch_upstream!(from)
        path ? dig_path(upstream, path, from, optional) : upstream
      end
    end

    private

    def fetch_upstream!(from)
      raise UnknownOutputKey, "unknown output key: #{from.inspect}" unless @previous_outputs.key?(from)

      @previous_outputs[from]
    end

    def dig_path(upstream, path, from, optional)
      value = path.split(".").reduce(upstream) do |node, seg|
        break nil if node.nil?

        node.is_a?(Array) ? node[seg.to_i] : node[seg]
      end

      return nil if value.nil? && optional
      raise MissingPath, "missing path #{path.inspect} in output #{from.inspect}" if value.nil?

      value
    end
  end
end
