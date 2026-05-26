module Orchestration
  class QueryExecutor
    include Orchestration::Executable
    extend Records::ModelResolver

    input_schema(
      table:         { "type" => "string" },
      column_name:   { "type" => "string" },
      column_values: { "type" => "array" },
      columns:       { "type" => "array" }
    )

    def self.call(table:, column_name:, column_values:, columns: nil, **)
      model   = resolve_model(table)
      records = model.where(column_name => column_values)
      rows    = records.map do |record|
        attrs = record.attributes
        columns ? attrs.slice(*columns) : attrs
      end

      # steep:ignore:start
      { table => rows }
      # steep:ignore:end
    rescue Records::ModelNotFound => error
      raise ArgumentError, error.message
    end
  end
end
