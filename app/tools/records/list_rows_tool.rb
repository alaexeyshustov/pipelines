module Records
  class ListRowsTool < RubyLLM::Tool
    include ModelResolver

    description "List rows in a database table."

    param :table,  type: :string,  desc: "Table name: application_mails or interviews", required: true
    param :limit,  type: :integer, desc: "Maximum number of rows to return, default is 50"
    param :offset, type: :integer, desc: "Number of rows to skip before starting to return rows, default is 0"

    def name = "list_rows"

    def execute(table:, limit: 50, offset: 0)
      model = resolve_model(table)
      scope = model.all
      scope = scope.offset(offset) if offset > 0
      scope = scope.limit(limit) if limit > 0
      rows  = model.as_rows(scope)
      { headers: model::COLUMN_NAMES, rows: rows, row_count: rows.size }
    rescue ModelNotFound => e
      { error: e.message }
    end
  end
end
