module Orchestration
  module Executors
    class Query
      include Orchestration::Executable
      extend Records::ModelResolver

      input_schema(
        table:         { "type" => "string" },
        column_name:   { "type" => "string" },
        column_values: { "type" => "array" },
        columns:       { "type" => "array" }
      )

      def self.call(table:, column_name:, column_values:, columns: nil, **_kwargs)
        new(table: table, column_name: column_name, column_values: column_values, columns: columns).execute
      end

      def initialize(table:, column_name:, column_values:, columns: nil, **_kwargs)
        @table         = table
        @column_name   = column_name
        @column_values = column_values
        @columns       = columns
      end

      def execute
        model   = self.class.resolve_model(@table)
        records = model.where(@column_name => @column_values).to_a # : Array[ApplicationRecord]
        rows    = records.map do |record|
          attrs = record.attributes # : Hash[String, untyped]
          @columns ? attrs.slice(*@columns) : attrs
        end

        { @table => rows }
      rescue Records::ModelNotFound => error
        raise ArgumentError, error.message
      end
    end
  end
end
