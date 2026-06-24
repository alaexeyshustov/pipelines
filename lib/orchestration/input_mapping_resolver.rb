module Orchestration
  class InputMappingResolver
    class UnknownOutputKey < StandardError; end
    class MissingPath < StandardError; end

    def initialize(input_mapping:, previous_outputs:)
      @input_mapping    = input_mapping
      @previous_outputs = previous_outputs
    end

    def resolve
      @input_mapping.transform_values { |spec| resolve_value(spec) }
    end

    def resolve_value(spec)
      return spec unless spec.is_a?(Hash)
      return spec["value"] if spec.key?("value")

      from     = spec["from"] # steep:ignore
      path     = spec["path"].presence && spec["path"].to_s  # : String?
      optional = spec["optional"] # : bool

      upstream = fetch_upstream!(from, optional:) # steep:ignore
      return nil if upstream.nil?
      path ? dig_path(upstream, path, from, optional) : upstream # steep:ignore
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
      node = upstream # : json_object_value
      path.split(".").each do |seg|
        node = traverse_node(node, seg) # steep:ignore
        break if node.nil?
      end

      return nil if node.nil? && optional
      raise MissingPath, "missing path #{path.inspect} in output #{from.inspect}" if node.nil?

      node
    end

    def traverse_node(node, seg)
      if node.is_a?(Array)
        seg.match?(/\A\d+\z/) ? node[seg.to_i] : nil
      elsif node.is_a?(Hash)
        node[seg]
      else
        nil
      end
    end
  end
end
