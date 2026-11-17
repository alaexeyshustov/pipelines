module Orchestration
  module Executors
    class Query
      include Orchestration::Executable
      extend Records::ModelResolver

      # Readable here on top of the model's tool columns.
      EXTRA_COLUMNS = %w[created_at].freeze

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
        validate_columns(model)
        records = model.where(@column_name => @column_values).to_a # : Array[ApplicationRecord]
        rows    = records.map do |record|
          attrs = record.attributes # : Hash[String, untyped]
          @columns ? attrs.slice(*@columns) : attrs
        end

        { @table => rows }
      rescue Records::ModelNotFound => error
        raise ArgumentError, error.message
      end

      private

      # Both come from input mappings, i.e. possibly from an upstream agent's output.
      def validate_columns(model)
        unknown = [ @column_name, *@columns ].map(&:to_s) - model.tool_column_names - EXTRA_COLUMNS
        raise ArgumentError, "Unknown column: #{unknown.join(', ')}" if unknown.any?
      end
    end
  end
end
