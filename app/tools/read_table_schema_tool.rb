class ReadTableSchemaTool < RubyLLM::Tool
  description "Return the column names for a database table."

  param :table, type: :string,
                desc: "Table name: application_mails or interviews",
                required: true

  def execute(table:)
    model = resolve_model(table)
    { headers: model::COLUMN_NAMES }
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
