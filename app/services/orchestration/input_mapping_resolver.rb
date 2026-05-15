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

        upstream = fetch_upstream!(from, optional:)
        next nil if upstream.nil?
        path ? dig_path(upstream, path, from, optional) : upstream
      end
    end

    private

    def fetch_upstream!(from, optional: false)
      unless @previous_outputs.key?(from)
        return nil if optional
        raise UnknownOutputKey, "unknown output key: #{from.inspect}"
      end

      @previous_outputs[from]
    end

    def dig_path(upstream, path, from, optional)
      value = path.split(".").reduce(upstream) do |node, seg|
        break nil if node.nil?

        if node.is_a?(Array)
          break nil unless seg.match?(/\A\d+\z/)
          node[seg.to_i]
        else
          node[seg]
        end
      end

      return nil if value.nil? && optional
      raise MissingPath, "missing path #{path.inspect} in output #{from.inspect}" if value.nil?

      value
    end
  end
end
