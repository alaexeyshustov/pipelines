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
        next spec unless spec.is_a?(Hash)
        next spec["value"] if spec.key?("value")

        from     = spec["from"] # steep:ignore
        path     = spec["path"].presence && spec["path"].to_s  # : String?
        optional = spec["optional"] # : bool

        upstream = fetch_upstream!(from, optional:) # steep:ignore
        next nil if upstream.nil?
        path ? dig_path(upstream, path, from, optional) : upstream # steep:ignore
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
      node = upstream # : json_object_value
      path.split(".").each do |seg|
        cur = node # : json_object_value
        if cur.nil?
          node = nil
        elsif cur.is_a?(Array)
          if seg.match?(/\A\d+\z/)
            node = cur[seg.to_i]
          else
            node = nil
            break
          end
        elsif cur.is_a?(Hash)
          node = cur[seg]
        else
          node = nil
        end
      end
      value = node

      return nil if value.nil? && optional
      raise MissingPath, "missing path #{path.inspect} in output #{from.inspect}" if value.nil?

      value
    end
  end
end
