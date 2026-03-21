# frozen_string_literal: true

class ReadTableRowsTool < RubyLLM::Tool
  description "Query rows from a database table, optionally filtering by a column value."

  param :table,        type: :string, desc: "Table name: application_mails or interviews", required: true
  param :column_name,  type: :string, desc: "Column name to filter on", required: false
  param :column_value, type: :string, desc: "Column value to match", required: false

  def execute(table:, column_name: nil, column_value: nil)
    model = resolve_model(table)
    scope = model.all
    scope = scope.where(column_name => column_value) if column_name && column_value
    rows  = model.as_rows(scope)
    { headers: model::COLUMN_NAMES, rows: rows, row_count: rows.size }
  end

  private

  def resolve_model(table)
    case table.to_s
    when "application_mails" then ApplicationMail
    when "interviews"        then Interview
    else raise ArgumentError, "Unknown table '#{table}'. Use: application_mails, interviews."
    end
  end
end
