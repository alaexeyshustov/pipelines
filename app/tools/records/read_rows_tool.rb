module Records
  class ReadRowsTool < RubyLLM::Tool
    include ModelResolver

    description "Query rows from a database table filtering by a column value. For example by id, email, or company name."

    param :table,        type: :string, desc: "Table name: application_mails or interviews", required: true
    param :column_name,  type: :string, desc: "Column name to filter on", required: true
    param :column_value, type: :string, desc: "Column value to match", required: true

    def name = "read_rows"

    def execute(table:, column_name:, column_value:)
      model = resolve_model(table)
      scope = model.all
      scope = scope.where(column_name => column_value) if column_name && column_value
      rows  = model.as_rows(scope)
      { headers: model::COLUMN_NAMES, rows: rows, row_count: rows.size }
    rescue ModelNotFound => e
      { error: e.message }
    end
  end
end
