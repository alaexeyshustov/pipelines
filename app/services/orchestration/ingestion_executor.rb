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

        result = execute_operation(acc, op)
        acc.replace(result)
      end
    end

    class << self
      private

      def execute_operation(output, op)
        case op.fetch("type")
        when "filter_by_ids" then apply_filter_by_ids(output, op)
        when "rename"        then apply_rename(output, op)
        when "pick"          then apply_pick(output, op)
        when "merge_by_index" then apply_merge_by_index(output, op)
        end
      end

      def apply_filter_by_ids(output, op)
        source   = op.fetch("source")
        ids_from = op.fetch("ids_from")
        dest     = op.fetch("output")

        id_items    = Array(dig_path(output, ids_from))
        allowed_ids = id_items.filter_map { |item| item_id(item) }.to_set

        source_items = Array(dig_path(output, source))
        filtered     = source_items.select { |item| (id = item_id(item)) && allowed_ids.include?(id) }

        output.merge(dest => filtered)
      end

      def dig_path(hash, path)
        hash.dig(*path.split("."))
      end

      def item_id(item)
        item.is_a?(Hash) ? item["id"].to_s : nil
      end

      def apply_rename(output, op)
        from = op.fetch("from").to_s
        to   = op.fetch("to").to_s

        output.transform_keys { |k| k == from ? to : k }
      end

      def apply_pick(output, op)
        keys = Array(op.fetch("keys"))
        output.slice(*keys)
      end

      def apply_merge_by_index(output, op)
        source  = op.fetch("source").to_s
        ids_key = op.fetch("ids").to_s
        inject  = op.fetch("inject").to_s
        dest    = op.fetch("output").to_s

        source_arr = Array(output.fetch(source, [])) # : Array[json_object]
        ids_arr    = Array(output.fetch(ids_key, []))
        count      = [ source_arr.size, ids_arr.size ].min

        merged = source_arr.first(count).map.with_index { |item, i| { inject => ids_arr[i] }.merge(item) }

        output.merge(dest => merged)
      end
    end
  end
end
