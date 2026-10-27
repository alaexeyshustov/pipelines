module Records
  class ReadRowsTool < RubyLLM::Tool
    include ModelResolver

    def self.readonly? = true

    description "Query rows from a database table filtering by a column value. For example by id, email, or company name."

    parameter :table,        type: :string, description: "Table name: application_mails or interviews", required: true
    parameter :column_name,  type: :string, description: "Column name to filter on"
    parameter :column_value, type: :string, description: "Column value to match"

    def name = "read_rows"

    def execute(table:, column_name: nil, column_value: nil)
      model = resolve_model(table)
      scope = model.all
      scope = scope.where(column_name => column_value) if column_name && column_value
      rows  = model.as_rows(scope)
      { headers: model.tool_column_names, rows: rows, row_count: rows.size }
    rescue ModelNotFound => e
      { error: e.message }
    end
  end
end
