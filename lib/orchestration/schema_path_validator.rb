module Orchestration
  class SchemaPathValidator
    def self.valid?(path, schema)
      new(schema).valid?(path)
    end

    def initialize(schema)
      @schema = schema
    end

    def valid?(path)
      current = @schema

      path.split(".").each do |seg|
        return false if current.nil?

        result = advance_schema_node(current, seg)
        return false if result == :invalid

        current = result
      end

      true
    end

    private

    def advance_schema_node(current, seg)
      case current["type"]
      when "object" then advance_through_object(current, seg)
      when "array"  then advance_through_array(current, seg)
      else :invalid
      end
    end

    def advance_through_object(current, seg)
      properties = current["properties"]
      return :invalid unless properties.is_a?(Hash)
      return :invalid unless properties.key?(seg)

      properties[seg]
    end

    def advance_through_array(current, seg)
      return :invalid unless seg.match?(/\A\d+\z/)

      current["items"].is_a?(Hash) ? current["items"] : nil
    end
  end
end
