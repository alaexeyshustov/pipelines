module Orchestration
  class QueryExecutor
    include Orchestration::Executable
    extend Records::ModelResolver

    def self.call(input, params = {})
      table         = params.fetch("table")
      column_name   = params.fetch("column_name")
      column_values = if (path = params["column_values_from"])
        Array(dig_path(input, path))
      else
        Array(params.fetch("column_values"))
      end
      columns = params["columns"]

      model   = resolve_model(table)
      records = model.where(column_name => column_values)
      rows    = records.map do |record|
        attrs = record.attributes
        columns ? attrs.slice(*columns) : attrs
      end

      { table => rows }
    rescue Records::ModelNotFound => error
      raise ArgumentError, error.message
    end

    class << self
      private

      def dig_path(hash, path)
        path.split(".").reduce(hash) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil }
      end
    end
  end
end
