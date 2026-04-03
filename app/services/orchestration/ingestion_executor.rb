module Orchestration
  class IngestionExecutor
    include Orchestration::Executable

    SUPPORTED_OPERATIONS = %w[filter_by_ids rename pick merge_by_index].freeze

    def self.call(input, params = {})
      operations = params.fetch("operations", [])
      output = input.dup

      operations.each_with_object(output) do |op, acc|
        type = op.fetch("type")
        raise ArgumentError, "unknown operation type: #{type}" unless SUPPORTED_OPERATIONS.include?(type)

        result = send(:"apply_#{type}", acc, op)
        acc.replace(result)
      end
    end

    class << self
      private

      def apply_filter_by_ids(output, op)
        source   = op.fetch("source")
        ids_from = op.fetch("ids_from")
        dest     = op.fetch("output")

        allowed_ids = dig_path(output, ids_from).then { |v| Array(v) }.map { |item| item["id"].to_s }.to_set
        filtered    = Array(output.fetch(source, [])).select { |item| allowed_ids.include?(item["id"].to_s) }

        output.merge(dest => filtered)
      end

      def dig_path(hash, path)
        keys = path.split(".")
        keys.reduce(hash) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil }
      end

      def apply_rename(output, op)
        from = op.fetch("from")
        to   = op.fetch("to")

        output.transform_keys { |k| k == from ? to : k }
      end

      def apply_pick(output, op)
        keys = op.fetch("keys")
        output.slice(*keys)
      end

      def apply_merge_by_index(output, op)
        source  = op.fetch("source")
        ids_key = op.fetch("ids")
        inject  = op.fetch("inject")
        dest    = op.fetch("output")

        source_arr = Array(output.fetch(source, []))
        ids_arr    = Array(output.fetch(ids_key, []))

        merged = source_arr.zip(ids_arr).take([ source_arr.length, ids_arr.length ].min).map do |item, id|
          { inject => id }.merge(item)
        end

        output.merge(dest => merged)
      end
    end
  end
end
